defmodule Appsatu.UploadConfig do
  @moduledoc """
  Centralized configuration for uploads.
  """

  def allowed_extensions, do: ~w(.jpg .jpeg .png .webp)

  def allowed_content_types, do: ~w(image/jpeg image/png image/webp)

  def max_file_size, do: 2 * 1024 * 1024

  def max_gallery_entries, do: 3

  def default_quality, do: 85
  def default_max_width, do: 1920
  def default_max_height, do: 1080

  @doc """
  Returns image processing config for a specific role.
  """
  def image_config("cover"), do: %{max_width: 1920, max_height: 1080, quality: 85}
  def image_config("thumbnail"), do: %{max_width: 400, max_height: 400, quality: 80}
  def image_config("gallery"), do: %{max_width: 1200, max_height: 800, quality: 80}
  def image_config("attachment"), do: %{max_width: 1920, max_height: 1080, quality: 85}
  def image_config(_role), do: %{max_width: 1920, max_height: 1080, quality: 85}
end
