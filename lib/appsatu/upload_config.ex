defmodule Appsatu.UploadConfig do
  @moduledoc """
  Centralized configuration for uploads.
  """

  def allowed_extensions, do: ~w(.jpg .jpeg .png .webp)

  def allowed_content_types, do: ~w(image/jpeg image/png image/webp)

  def max_file_size, do: 2 * 1024 * 1024

  def max_gallery_entries, do: 3

  def image_quality, do: 85

  def max_image_width, do: 1920
  def max_image_height, do: 1080

  def thumbnail_quality, do: 80
  def thumbnail_max_width, do: 400
  def thumbnail_max_height, do: 400
end