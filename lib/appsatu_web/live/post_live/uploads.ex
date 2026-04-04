defmodule AppsatuWeb.PostLive.Uploads do
  @moduledoc false

  alias Appsatu.Blog.PostImage
  alias Appsatu.Uploaders.PostImage, as: PostImageUploader

  def ensure_upload_dir, do: :ok

  def prepare_upload_attrs(temp_path, client_name, content_type, post, role) do
    normalized_content_type = content_type || "application/octet-stream"
    filename = unique_filename(client_name, normalized_content_type)

    case File.read(temp_path) do
      {:ok, binary} ->
        upload = %{filename: filename, binary: binary}

        {:ok,
         %{
           post_id: post.id,
           role: role,
           filename: upload,
           content_type: normalized_content_type,
           size: byte_size(binary)
         }}

      {:error, _reason} ->
        {:error, "Gagal membaca file upload"}
    end
  end

  def delete_uploaded_file(%PostImage{} = image) do
    case image.filename do
      nil -> :ok
      filename -> PostImageUploader.delete({filename, image})
    end
  end

  defp normalize_extension("", "image/jpeg"), do: ".jpg"
  defp normalize_extension("", "image/png"), do: ".png"
  defp normalize_extension("", "image/webp"), do: ".webp"
  defp normalize_extension("", _), do: ".bin"
  defp normalize_extension(ext, _), do: ext

  defp unique_filename(client_name, content_type) do
    extension =
      client_name
      |> Path.extname()
      |> String.downcase()
      |> normalize_extension(content_type)

    Ecto.UUID.generate() <> extension
  end

end
