defmodule AppsatuWeb.PostLive.Components do
  @moduledoc """
  Module ini berisi komponen UI reusable untuk PostLive.
  Semua komponen menggunakan HEEx template dan Tailwind CSS.
  """
  use AppsatuWeb, :html

  # ============================================================
  # ATTRIBUTES - Definisi parameter yang diterima komponen
  # ============================================================

  # --- post_form_section attributes ---
  attr :title, :string, required: true      # Judul form (Create Post / Edit Post)
  attr :subtitle, :string, required: true   # Subtitle/deskripsi form
  attr :form, Phoenix.HTML.Form, required: true  # Form struct dari to_form()
  attr :categories, :list, required: true   # List category untuk dropdown
  attr :tags, :list, required: true         # List tags untuk checkbox
  attr :uploads, :map, required: true       # Map upload configs (cover, thumbnail, etc)
  attr :action, :atom, required: true      # :new atau :edit
  attr :post, :map, default: nil           # Post struct (untuk edit mode)
  attr :preview_image, :map, default: nil  # Image yang sedang di-preview
  attr :submit_disabled, :boolean, default: false  # Disable submit button
  attr :selected_tag_ids, :list, default: []      # Tag IDs yang dipilih
  attr :selected_tag_count, :integer, default: 0   # Jumlah tag dipilih
  attr :body_length, :integer, default: 0          # Panjang karakter body

  # --- Main Form Component ---
  # Renders form lengkap untuk create/edit post
  # Includes: title, category, body, tags, upload fields, existing media
  def post_form_section(assigns) do
    ~H"""
    <section class="space-y-6">
      <div class="rounded-3xl bg-gradient-to-r from-orange-400 via-amber-400 to-lime-400 p-[1px] shadow-lg">
        <div class="rounded-3xl bg-base-100 p-6 sm:p-8">
          <h1 class="text-3xl font-bold tracking-tight">{@title}</h1>
          
          <p class="mt-1 text-base-content/60">{@subtitle}</p>
        </div>
      </div>
      
      <div class="rounded-3xl border border-base-300 bg-base-100 p-6 shadow-sm sm:p-8">
        <.form for={@form} id="post-form" phx-change="validate" phx-submit="save" class="space-y-5">
          <div class="grid gap-4 sm:grid-cols-2">
            <div class="space-y-1">
              <p class="text-xs font-semibold uppercase tracking-wide text-base-content/60">Title</p>
              
              <.input
                field={@form[:title]}
                type="text"
                placeholder="Tulis judul post yang kuat"
                class="input input-bordered w-full text-base font-semibold"
              />
            </div>
            
            <div class="space-y-1">
              <p class="text-xs font-semibold uppercase tracking-wide text-base-content/60">
                Category
              </p>
              
              <.input
                field={@form[:category_id]}
                type="select"
                options={Enum.map(@categories, &{&1.name, &1.id})}
                prompt="Pilih kategori"
                class="select select-bordered w-full"
              />
            </div>
          </div>
          
          <div class="space-y-1">
            <div class="flex items-center justify-between">
              <p class="text-xs font-semibold uppercase tracking-wide text-base-content/60">Body</p>
              
              <p class="text-xs text-base-content/50">{@body_length} chars</p>
            </div>
            
            <.input
              field={@form[:body]}
              type="textarea"
              placeholder="Tulis isi post yang jelas dan mudah dibaca"
              class="textarea textarea-bordered min-h-40 w-full leading-relaxed"
            />
          </div>
          
          <div class="space-y-2">
            <div class="flex items-center justify-between">
              <label class="label mb-0">Tags</label>
              <span class="badge badge-info badge-soft rounded-full text-[10px] font-semibold">
                {@selected_tag_count} selected
              </span>
            </div>
             <input type="hidden" name="post[tag_ids][]" value="" />
            <div class="flex flex-wrap gap-2">
              <label :for={tag <- @tags} class="group cursor-pointer">
                <input
                  type="checkbox"
                  name="post[tag_ids][]"
                  value={tag.id}
                  checked={to_string(tag.id) in @selected_tag_ids}
                  class="peer sr-only"
                />
                <span class="badge rounded-full border border-base-300 bg-base-100 px-3 py-3 text-xs font-semibold uppercase tracking-wide transition group-hover:border-primary peer-checked:border-info peer-checked:bg-info/15 peer-checked:text-info">
                  {tag.name}
                </span>
              </label>
            </div>
          </div>
          
          <div class="rounded-2xl border border-base-300 bg-base-50/30 p-4">
            <p class="mb-3 text-sm font-semibold uppercase tracking-wide text-base-content/70">
              Media Upload
            </p>
            
            <p class="mb-4 text-xs text-base-content/60">
              Cover, thumbnail, attachment, dan gallery diupload terpisah.
            </p>
            
            <div class="grid gap-4 md:grid-cols-2">
              <.upload_field upload={@uploads.cover_image} label="Cover Image" target="cover_image" />
              <.upload_field
                upload={@uploads.thumbnail_image}
                label="Thumbnail Image"
                target="thumbnail_image"
              /> <.upload_field upload={@uploads.attachment} label="Attachment" target="attachment" />
              <.upload_field
                upload={@uploads.gallery_images}
                label="Gallery Images"
                target="gallery_images"
              />
            </div>
          </div>
          
          <div
            :if={@action == :edit && @post && @post.images != []}
            class="rounded-2xl border border-base-300 p-4"
          >
            <div class="mb-3 flex items-center justify-between">
              <p class="text-sm font-semibold uppercase tracking-wide text-base-content/70">
                Existing Media
              </p>
              
              <p class="text-xs text-base-content/50">Klik gambar untuk preview</p>
            </div>
            
            <div class="grid grid-cols-2 gap-3 sm:grid-cols-4">
              <div
                :for={image <- @post.images}
                class="overflow-hidden rounded-xl border border-base-300 bg-base-100"
              >
                <button
                  type="button"
                  phx-click="open-image-preview"
                  phx-value-url={image_url(image)}
                  phx-value-filename={filename_label(image.filename)}
                  phx-value-role={image.role}
                  class="group block w-full cursor-pointer"
                >
                  <div class="relative">
                    <img
                      src={image_url(image)}
                      alt={filename_label(image.filename)}
                      class="h-24 w-full object-cover transition duration-200 group-hover:scale-[1.02] group-hover:opacity-90"
                    />
                    <div class="pointer-events-none absolute inset-0 flex items-center justify-center bg-black/0 transition group-hover:bg-black/25">
                      <span class="rounded-full border border-white/50 bg-black/35 px-2 py-1 text-[10px] font-semibold uppercase tracking-wide text-white opacity-0 transition group-hover:opacity-100">
                        preview
                      </span>
                    </div>
                  </div>
                </button>
                <div class="flex items-center justify-between px-2 py-2">
                  <span class="text-[10px] font-semibold uppercase tracking-wide text-base-content/60">
                    {image.role}
                  </span>
                  <button
                    type="button"
                    phx-click="delete-existing-image"
                    phx-value-id={image.id}
                    data-confirm="Hapus media ini?"
                    class="btn btn-xs btn-error btn-soft"
                  >
                    <.icon name="hero-trash" class="size-3" />
                  </button>
                </div>
              </div>
            </div>
          </div>
           <.input field={@form[:published]} type="checkbox" label="Published" />
          <div class="flex flex-wrap gap-3 pt-2">
            <.button
              type="submit"
              disabled={@submit_disabled}
              class="btn btn-primary rounded-full px-7"
            >
              <.icon name="hero-check-circle" class="size-5" /> {if @action == :new,
                do: "Create Post",
                else: "Update Post"}
            </.button>
            <.button navigate={~p"/posts"} class="btn btn-ghost rounded-full">Cancel</.button>
          </div>
        </.form>
      </div>
    </section>
    """
  end

  # ============================================================
  # IMAGE PREVIEW MODAL
  # Muncul saat user klik gambar existing untuk preview
  # ============================================================

  attr :preview_image, :map, default: nil  # Image yang di-preview (map dengan :url, :filename, :role)

  # Renders modal overlay dengan gambar besar
  # Juga menampilkan filename dan role gambar
  # Close dengan klik tombol X, klik luar modal, atau tekan Escape
  def image_preview_modal(assigns) do
    ~H"""
    <%= if @preview_image do %>
      <div
        class="fixed inset-0 z-50 flex items-center justify-center bg-black/70 p-4 backdrop-blur-sm"
        phx-window-keydown="close-image-preview"
        phx-key="escape"
      >
        <div
          class="relative w-full max-w-4xl overflow-hidden rounded-2xl border border-white/15 bg-base-100/95 shadow-2xl"
          phx-click-away="close-image-preview"
        >
          <div class="absolute right-3 top-3 z-10">
            <button
              type="button"
              phx-click="close-image-preview"
              class="group inline-flex h-9 w-9 items-center justify-center rounded-full border border-white/20 bg-black/30 text-white shadow-lg transition hover:scale-105 hover:bg-black/50 focus:outline-none focus:ring-2 focus:ring-white/60"
              aria-label="Close preview"
            >
              <.icon name="hero-x-mark" class="size-4 transition group-hover:rotate-90" />
            </button>
          </div>
          
          <img
            src={@preview_image.url}
            alt={@preview_image.filename}
            class="max-h-[75vh] w-full bg-black/40 object-contain"
          />
          <div class="flex items-center justify-between border-t border-base-300/70 px-4 py-3">
            <span class="badge badge-info badge-soft rounded-full text-[10px] font-semibold uppercase tracking-wide">
              {@preview_image.role}
            </span>
            <span class="max-w-[70%] truncate text-xs text-base-content/60">
              {@preview_image.filename}
            </span>
          </div>
        </div>
      </div>
    <% end %>
    """
  end

  # ============================================================
  # UPLOAD FIELD COMPONENT
  # Dropzone untuk upload file (cover, thumbnail, attachment, gallery)
  # ============================================================

  attr :upload, :map, required: true      # Upload struct dari Phoenix LiveView
  attr :label, :string, required: true    # Label tampilan (e.g. "Cover Image")
  attr :target, :string, required: true   # Target key (e.g. "cover_image")

  # Renders drag-and-drop zone dengan progress bar
  # Menggunakan live_file_input untuk Phoenix upload
  defp upload_field(assigns) do
    ~H"""
    <div class="space-y-2 rounded-xl border border-base-300 p-3">
      <label class="text-sm font-medium">{@label}</label>
      <div
        phx-drop-target={@upload.ref}
        class="relative rounded-xl border-2 border-dashed border-base-300 bg-base-200/30 p-4 transition hover:border-primary"
      >
        <.live_file_input
          upload={@upload}
          class="absolute inset-0 h-full w-full cursor-pointer opacity-0"
        />
        <%= if @upload.entries == [] do %>
          <div class="pointer-events-none text-center">
            <p class="text-sm font-medium">Drag & drop file ke sini</p>
            
            <p class="text-xs text-base-content/60">atau klik area ini untuk memilih file</p>
          </div>
        <% else %>
          <div class="pointer-events-none grid place-items-center gap-2">
            <div
              :for={entry <- @upload.entries}
              class="w-full max-w-44 overflow-hidden rounded-lg border border-base-300 bg-base-100"
            >
              <div class="flex h-24 items-center justify-center text-center text-xs text-base-content/60">
                {entry.client_name}
              </div>
            </div>
          </div>
        <% end %>
      </div>
      
      <p :for={err <- upload_errors(@upload)} class="text-xs text-error">
        {upload_error_to_text(err)}
      </p>
      
      <div :for={entry <- @upload.entries} class="space-y-1">
        <div class="flex items-center justify-between text-xs">
          <span class="truncate">{entry.client_name}</span>
          <button
            type="button"
            phx-click="cancel-upload"
            phx-value-ref={entry.ref}
            phx-value-target={@target}
            class="link link-error"
          >
            cancel
          </button>
        </div>
        
        <progress class="progress progress-primary w-full" value={entry.progress} max="100">
          {entry.progress}%
        </progress>
        <p :for={err <- upload_errors(@upload, entry)} class="text-xs text-error">
          {upload_error_to_text(err)}
        </p>
      </div>
    </div>
    """
  end

  # ============================================================
  # HELPER FUNCTIONS
  # ============================================================

  # --- Convert upload error atom ke text Indonesia ---
  defp upload_error_to_text(:too_large), do: "Ukuran file terlalu besar (maks 5MB)"
  defp upload_error_to_text(:not_accepted),
    do: "Tipe file tidak didukung. Gunakan JPG, JPEG, PNG, atau WEBP"
  defp upload_error_to_text(:too_many_files), do: "Jumlah file melebihi batas"
  defp upload_error_to_text(_), do: "Upload gagal"

  # --- Ambil filename dari image struct ---
  defp filename_label(%{file_name: file_name}) when is_binary(file_name), do: file_name
  defp filename_label(file_name) when is_binary(file_name), do: file_name
  defp filename_label(_), do: "uploaded-file"

  # --- Bangun URL untuk image ---
  # Jika image punya :url field, gunakan itu
  # Jika tidak, bangun path dari post_id/role/filename
  defp image_url(image) do
    case Map.get(image, :url) do
      url when is_binary(url) and url != "" ->
        url

      _ ->
        case filename_label(image.filename) do
          "uploaded-file" -> image.url
          file_name -> "/uploads/posts/#{image.post_id}/#{image.role}/#{file_name}"
        end
    end
  end
end
