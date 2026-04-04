defmodule AppsatuWeb.PostLive.Uploads do
  @moduledoc false

  alias Appsatu.Blog.PostImage
  alias Appsatu.Uploaders.PostImage, as: PostImageUploader

  @allowed_extensions ~w(.jpg .jpeg .png .webp)
  @allowed_content_types ~w(image/jpeg image/png image/webp)

  def prepare_upload_attrs(temp_path, client_name, content_type, post, role) do
    normalized_content_type = content_type || "application/octet-stream"

    with {:ok, filename} <- unique_filename(client_name, normalized_content_type),
         {:ok, binary} <- File.read(temp_path),
         :ok <- validate_binary_content_type(binary, normalized_content_type) do
      upload = %{filename: filename, binary: binary}

      {:ok,
       %{
         post_id: post.id,
         role: role,
         filename: upload,
         content_type: normalized_content_type,
         size: byte_size(binary)
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

  def delete_uploaded_file(%PostImage{} = image) do
    case image.filename do
      nil -> :ok
      filename -> PostImageUploader.delete({filename, image})
    end
  end

  defp normalize_extension("", "image/jpeg"), do: {:ok, ".jpg"}
  defp normalize_extension("", "image/png"), do: {:ok, ".png"}
  defp normalize_extension("", "image/webp"), do: {:ok, ".webp"}
  defp normalize_extension("", _), do: {:error, :invalid_extension}

  defp normalize_extension(ext, _) when ext in @allowed_extensions, do: {:ok, ext}
  defp normalize_extension(_ext, _), do: {:error, :invalid_extension}

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

  defp validate_binary_content_type(binary, claimed_content_type) when is_binary(binary) do
    with true <- claimed_content_type in @allowed_content_types,
         detected_type when detected_type in @allowed_content_types <- detect_content_type(binary),
         true <- detected_type == claimed_content_type do
      :ok
    else
      _ -> {:error, :invalid_content}
    end
  end

  defp detect_content_type(<<0xFF, 0xD8, 0xFF, _rest::binary>>), do: "image/jpeg"
  defp detect_content_type(<<0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, _rest::binary>>), do: "image/png"

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

  defp detect_content_type(_binary), do: nil

  defp upload_error(:invalid_extension),
    do: {:error, "Tipe file tidak didukung. Gunakan JPG, JPEG, PNG, atau WEBP"}

  defp upload_error(:invalid_content),
    do: {:error, "Isi file tidak sesuai dengan tipe gambar yang diizinkan"}

  defp upload_error(:read_failed), do: {:error, "Gagal membaca file upload"}
end
