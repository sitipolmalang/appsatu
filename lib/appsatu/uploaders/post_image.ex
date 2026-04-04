defmodule Appsatu.Uploaders.PostImage do
  use Waffle.Definition
  use Waffle.Ecto.Definition

  @versions [:original]
  @allowed_extensions ~w(.jpg .jpeg .png .webp)

  def validate({file, _scope}) do
    extension =
      file.file_name
      |> Path.extname()
      |> String.downcase()

    if extension in @allowed_extensions do
      :ok
    else
      {:error, "Tipe file tidak didukung. Gunakan JPG, JPEG, PNG, atau WEBP"}
    end
  end

  def filename(_version, {file, _scope}) do
    Path.basename(file.file_name, Path.extname(file.file_name))
  end

  def storage_dir(_version, {_file, scope}) do
    role = scope.role || "unknown"
    post_id = scope.post_id || "unscoped"
    "uploads/posts/#{post_id}/#{role}"
  end
end
