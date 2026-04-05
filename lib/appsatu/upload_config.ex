defmodule Appsatu.UploadConfig do
  @moduledoc """
  Module ini menyimpan semua konfigurasi untuk file upload.
  Berisi: allowed extensions, content types, max size, dan image processing config.
  """

  # ============================================================
  # ALLOWED FILE TYPES
  # extensions: untuk validasi berdasarkan file extension
  # content_types: untuk validasi berdasarkan MIME type
  # ============================================================

  # Extension yang diizinkan (dot notation)
  def allowed_extensions, do: ~w(.jpg .jpeg .png .webp)

  # MIME type yang diizinkan
  def allowed_content_types, do: ~w(image/jpeg image/png image/webp)

  # ============================================================
  # SIZE LIMITS
  # max_file_size: 2MB (2 * 1024 * 1024 = 2,097,152 bytes)
  # max_gallery_entries: maksimal 3 gambar per gallery
  # ============================================================

  # Ukuran maksimal per file (2MB)
  def max_file_size, do: 2 * 1024 * 1024

  # Jumlah maksimal gambar gallery
  def max_gallery_entries, do: 3

  # ============================================================
  # DEFAULT IMAGE PROCESSING
  # quality: 85% (balance antara kualitas dan ukuran file)
  # max_width/height: batas maksimal dimensi gambar
  # ============================================================

  # Kualitas gambar default (1-100)
  def default_quality, do: 85
  # Lebar maksimal default
  def default_max_width, do: 1920
  # Tinggi maksimal default
  def default_max_height, do: 1080

  # ============================================================
  # IMAGE CONFIG BY ROLE
  # Setiap role (cover, thumbnail, gallery, attachment) punya
  # konfigurasi berbeda untuk optimize ukuran dan kualitas
  # ============================================================

  @doc """
  Returns image processing config untuk role tertentu.
  
  ## Roles:
  - "cover": Gambar utama post (1920x1080, quality 85%)
  - "thumbnail": Preview kecil (400x400, quality 80%)
  - "gallery": Galeri gambar (1200x800, quality 80%)
  - "attachment": File attachment (1920x1080, quality 85%)
  - default: Fallback jika role tidak dikenali
  """

  # Cover image: HD resolution, high quality
  def image_config("cover"), do: %{max_width: 1920, max_height: 1080, quality: 85}
  # Thumbnail: Persegi, lebih kecil dan quality sedikit lebih rendah
  def image_config("thumbnail"), do: %{max_width: 400, max_height: 400, quality: 80}
  # Gallery: Medium resolution, balanced
  def image_config("gallery"), do: %{max_width: 1200, max_height: 800, quality: 80}
  # Attachment: Sama seperti cover
  def image_config("attachment"), do: %{max_width: 1920, max_height: 1080, quality: 85}
  # Default fallback
  def image_config(_role), do: %{max_width: 1920, max_height: 1080, quality: 85}
end
