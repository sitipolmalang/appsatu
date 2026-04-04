defmodule AppsatuWeb.PostLive.Uploads do
  @moduledoc false

  def ensure_upload_dir do
    case File.mkdir_p(upload_dir()) do
      :ok -> :ok
      {:error, _reason} -> {:error, "Folder upload tidak bisa dibuat"}
    end
  end

  def copy_upload(temp_path, client_name, content_type) do
    normalized_content_type = content_type || "application/octet-stream"

    extension =
      client_name
      |> Path.extname()
      |> String.downcase()
      |> normalize_extension(normalized_content_type)

    filename = Ecto.UUID.generate() <> extension
    destination = Path.join(upload_dir(), filename)

    case File.cp(temp_path, destination) do
      :ok ->
        size =
          case File.stat(destination) do
            {:ok, stat} -> stat.size
            _ -> 0
          end

        {:ok,
         %{
           url: "/uploads/" <> filename,
           filename: filename,
           content_type: normalized_content_type,
           size: size,
           disk_path: destination
         }}

      {:error, _reason} ->
        {:error, "Gagal menyimpan file upload"}
    end
  end

  def build_cover_from_thumbnail(nil), do: {:ok, nil}

  def build_cover_from_thumbnail(thumbnail) do
    cover_filename = Ecto.UUID.generate() <> ".jpg"
    cover_disk_path = Path.join(upload_dir(), cover_filename)

    case compress_image(thumbnail.disk_path, cover_disk_path) do
      :ok ->
        size =
          case File.stat(cover_disk_path) do
            {:ok, stat} -> stat.size
            _ -> 0
          end

        {:ok,
         %{
           role: "cover",
           url: "/uploads/" <> cover_filename,
           filename: cover_filename,
           content_type: "image/jpeg",
           size: size,
           disk_path: cover_disk_path
         }}

      {:error, _reason} ->
        {:error, "Gagal membuat cover otomatis dari thumbnail"}
    end
  end

  def delete_uploaded_file(url) do
    filename = Path.basename(url)
    path = Path.join(upload_dir(), filename)
    File.rm(path)
  end

  defp compress_image(source_path, target_path) do
    case System.find_executable("magick") do
      nil ->
        case File.cp(source_path, target_path) do
          :ok -> :ok
          {:error, reason} -> {:error, reason}
        end

      magick ->
        case System.cmd(magick, [
               source_path,
               "-auto-orient",
               "-strip",
               "-thumbnail",
               "420x420>",
               "-quality",
               "68",
               target_path
             ]) do
          {_, 0} -> :ok
          {_output, _code} -> {:error, :convert_failed}
        end
    end
  end

  defp normalize_extension("", "image/jpeg"), do: ".jpg"
  defp normalize_extension("", "image/png"), do: ".png"
  defp normalize_extension("", "image/webp"), do: ".webp"
  defp normalize_extension("", _), do: ".bin"
  defp normalize_extension(ext, _), do: ext

  defp upload_dir do
    Path.join(Application.app_dir(:appsatu, "priv/static"), "uploads")
  end
end
