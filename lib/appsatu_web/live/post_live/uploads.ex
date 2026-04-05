defmodule AppsatuWeb.PostLive.Uploads do
  @moduledoc """
  Module ini berisi helper functions untuk memproses file upload.
  Berisi logic untuk: prepare upload, compress image, validate file, delete file.
  """
  
  # --- Context Aliases ---
  alias Appsatu.Blog.PostImage        # Model untuk gambar post
  alias Appsatu.UploadConfig          # Konfigurasi upload (allowed types, max size, dll)
  alias Appsatu.Uploaders.PostImage, as: PostImageUploader  # Uploader untuk delete file

  # --- Configuration dari UploadConfig ---
  @allowed_extensions UploadConfig.allowed_extensions()     # [.jpg, .jpeg, .png, .webp]
  @allowed_content_types UploadConfig.allowed_content_types()  # ["image/jpeg", "image/png", "image/webp"]

  # ============================================================
  # MAIN FUNCTION - Prepare Upload Attributes
  # Dipanggil dari post_live.ex saat user submit form
  # Flow: validate -> compress -> return attributes untuk disimpan ke DB
  # ============================================================

  # Params:
  # - temp_path: Path sementara file upload di server
  # - client_name: Nama file asli dari browser
  # - content_type: Tipe file dari browser (image/jpeg, dll)
  # - post: Struct Post yang sedang di-create/edit
  # - role: "cover", "thumbnail", "attachment", atau "gallery"
  #
  # Returns: {:ok, %{post_id, role, filename, content_type, size}}
  def prepare_upload_attrs(temp_path, client_name, content_type, post, role) do
    # Default ke octet-stream jika content_type nil
    normalized_content_type = content_type || "application/octet-stream"

    with {:ok, filename} <- unique_filename(client_name, normalized_content_type),
         # 1. Generate unique filename
         {:ok, binary} <- File.read(temp_path),
         # 2. Baca file dari temp path
         :ok <- validate_binary_content_type(binary, normalized_content_type) do
         # 3. Validasi content type dengan membaca binary header

      # 4. Compress image sesuai role (cover, thumbnail, dll)
      compressed = compress_image(binary, role)

      # 5. Return attributes untuk disimpan ke PostImage
      upload = %{filename: filename, binary: compressed.binary, original_size: byte_size(binary)}

      {:ok,
       %{
         post_id: post.id,
         role: role,
         filename: upload,
         content_type: normalized_content_type,
         size: byte_size(compressed.binary)
       }}
    else
      {:error, :invalid_extension} ->
        upload_error(:invalid_extension)

      {:error, :invalid_content} ->
        upload_error(:invalid_content)

      {:error, _reason} ->
        upload_error(:read_failed)
    end
  end

  # ============================================================
  # IMAGE COMPRESSION
  # Compress dan resize image berdasarkan role config
  # ============================================================

  # Buka image dengan Mogrify, lalu resize dan compress sesuai config
  defp compress_image(binary, role) do
    config = UploadConfig.image_config(role)

    image =
      binary
      |> Mogrify.open()

    resized = maybe_resize(image, config)

    compressed =
      resized
      |> maybe_set_quality(config)
      |> Mogrify.save()

    %{binary: compressed.binary}
  rescue
    # Jika gagal compress (misal bukan image), return original
    _ -> %{binary: binary}
  end

  # --- Resize hanya jika image lebih besar dari max config ---
  defp maybe_resize(image, %{max_width: max_w, max_height: max_h}) do
    w = image.width || 0
    h = image.height || 0

    if w > max_w or h > max_h do
      # Hitung scale untuk fit dalam box
      scale = min(max_w / w, max_h / h)
      Mogrify.resize(image, "#{Float.round(scale * 100)}%")
    else
      image
    end
  end

  # --- Set quality jika config ada ---
  defp maybe_set_quality(image, %{quality: quality}) do
    Mogrify.custom(image, "quality", "#{quality}")
  end

  # ============================================================
  # PREPARE UPLOAD FROM PLUG
  # Untuk upload dari Plug.Upload (fallback/joseki)
  # ============================================================
  def prepare_upload_from_plug(%Plug.Upload{} = upload, role) do
    with {:ok, filename} <- unique_filename(upload.filename, upload.content_type),
         {:ok, %{size: size}} <- File.stat(upload.path),
         {:ok, binary} <- File.read(upload.path),
         :ok <- validate_binary_content_type(binary, upload.content_type) do
      {:ok,
       %{
         role: role,
         filename: %Plug.Upload{upload | filename: filename},
         content_type: upload.content_type,
         size: size
       }}
    else
      {:error, :invalid_extension} ->
        upload_error(:invalid_extension)

      {:error, :invalid_content} ->
        upload_error(:invalid_content)

      {:error, _reason} ->
        upload_error(:read_failed)
    end
  end

  # ============================================================
  # DELETE UPLOADED FILE
  # Hapus file dari storage (local/remote) saat post/image dihapus
  # ============================================================
  def delete_uploaded_file(%PostImage{} = image) do
    case image.filename do
      nil -> :ok  # Tidak ada filename, tidak perlu hapus
      filename -> PostImageUploader.delete({filename, image})
    end
  end

  # ============================================================
  # HELPER FUNCTIONS - Filename & Extension
  # ============================================================

  # --- Normalize extension berdasarkan content_type jika ext kosong ---
  defp normalize_extension("", "image/jpeg"), do: {:ok, ".jpg"}
  defp normalize_extension("", "image/png"), do: {:ok, ".png"}
  defp normalize_extension("", "image/webp"), do: {:ok, ".webp"}
  defp normalize_extension("", _), do: {:error, :invalid_extension}

  # --- Validasi extension terhadap allowed list ---
  defp normalize_extension(ext, _) when ext in @allowed_extensions, do: {:ok, ext}
  defp normalize_extension(_ext, _), do: {:error, :invalid_extension}

  # --- Generate unique filename dengan UUID ---
  # Contoh: "abc123-def456.jpg"
  defp unique_filename(client_name, content_type) do
    client_name
    |> Path.extname()
    |> String.downcase()
    |> normalize_extension(content_type)
    |> case do
      {:ok, extension} -> {:ok, Ecto.UUID.generate() <> extension}
      {:error, :invalid_extension} -> {:error, :invalid_extension}
    end
  end

  # ============================================================
  # CONTENT TYPE VALIDATION
  # Validasi dengan membaca binary header (magic bytes)
  # ============================================================

  # Validasi: claimed type harus dalam allowed list
  # Dan detected type dari binary harus sama dengan claimed
  defp validate_binary_content_type(binary, claimed_content_type) when is_binary(binary) do
    with true <- claimed_content_type in @allowed_content_types,
         detected_type when detected_type in @allowed_content_types <- detect_content_type(binary),
         true <- detected_type == claimed_content_type do
      :ok
    else
      _ -> {:error, :invalid_content}
    end
  end

  # --- Detect content type dari binary header (magic bytes) ---
  # JPEG: FF D8 FF
  defp detect_content_type(<<0xFF, 0xD8, 0xFF, _rest::binary>>), do: "image/jpeg"

  # PNG: 89 50 4E 47 0D 0A 1A 0A
  defp detect_content_type(<<0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, _rest::binary>>),
    do: "image/png"

  # WEBP: RIFF _size_ WEBP
  defp detect_content_type(<<
        0x52,
        0x49,
        0x46,
        0x46,
        _size::binary-size(4),
        0x57,
        0x45,
        0x42,
        0x50,
        _rest::binary
      >>),
      do: "image/webp"

  # Unknown
  defp detect_content_type(_binary), do: nil

  # ============================================================
  # ERROR MESSAGES
  # ============================================================

  defp upload_error(:invalid_extension),
    do: {:error, "Tipe file tidak didukung. Gunakan JPG, JPEG, PNG, atau WEBP"}

  defp upload_error(:invalid_content),
    do: {:error, "Isi file tidak sesuai dengan tipe gambar yang diizinkan"}

  defp upload_error(:read_failed), do: {:error, "Gagal membaca file upload"}
end
