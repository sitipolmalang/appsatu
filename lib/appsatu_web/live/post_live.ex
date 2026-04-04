defmodule AppsatuWeb.PostLive do
  use AppsatuWeb, :live_view

  alias Appsatu.Blog
  alias Appsatu.Blog.Post

  @allowed_upload_types ~w(.jpg .jpeg .png .webp)
  @max_upload_size 5 * 1024 * 1024

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:current_scope, nil)
      |> assign(:categories, Blog.list_categories())
      |> assign(:tags, Blog.list_tags())
      |> assign(:post, nil)
      |> assign(:page_title, "Posts")
      |> stream(:posts, [])
      |> allow_upload(:thumbnail_image,
        accept: @allowed_upload_types,
        max_entries: 1,
        max_file_size: @max_upload_size,
        auto_upload: true
      )
      |> allow_upload(:attachment,
        accept: @allowed_upload_types,
        max_entries: 1,
        max_file_size: @max_upload_size,
        auto_upload: true
      )
      |> allow_upload(:gallery_images,
        accept: @allowed_upload_types,
        max_entries: 8,
        max_file_size: @max_upload_size,
        auto_upload: true
      )

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    case socket.assigns.live_action do
      :index ->
        posts = Blog.list_posts()

        {:noreply,
         socket
         |> assign(:page_title, "Posts")
         |> stream(:posts, posts, reset: true)}

      :new ->
        changeset =
          %Post{}
          |> Blog.change_post()
          |> Ecto.Changeset.put_change(:tag_ids, [])

        {:noreply,
         socket
         |> assign(:page_title, "Create Post")
         |> assign(:post, nil)
         |> assign(:form, to_form(changeset))}

      :edit ->
        post = Blog.get_post!(params["id"])

        changeset =
          post
          |> Blog.change_post()
          |> Ecto.Changeset.put_change(:tag_ids, Enum.map(post.tags, & &1.id))

        {:noreply,
         socket
         |> assign(:page_title, "Edit Post")
         |> assign(:post, post)
         |> assign(:form, to_form(changeset))}

      :show ->
        post = Blog.get_post!(params["id"])

        {:noreply,
         socket
         |> assign(:page_title, "Post Detail")
         |> assign(:post, post)}
    end
  end

  @impl true
  def handle_event("validate", %{"post" => post_params}, socket) do
    post = socket.assigns.post || %Post{}
    params = Map.put_new(post_params, "tag_ids", [])

    changeset =
      post
      |> Blog.change_post(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  def handle_event("save", %{"post" => post_params}, socket) do
    case any_uploads_in_progress?(socket) do
      true ->
        {:noreply, put_flash(socket, :error, "Upload masih berjalan, tunggu sampai selesai")}

      false ->
        case any_upload_errors?(socket) do
          true ->
            {:noreply, put_flash(socket, :error, "Masih ada file upload yang tidak valid")}

          false ->
            save_post(socket, post_params)
        end
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    post = Blog.get_post!(id)
    {:ok, _deleted_post} = Blog.delete_post(post)

    {:noreply,
     socket
     |> put_flash(:info, "Post deleted")
     |> stream_delete(:posts, post)}
  end

  def handle_event("delete-existing-image", %{"id" => image_id}, socket) do
    post = socket.assigns.post

    with {id, ""} <- Integer.parse(image_id),
         %{} = image <- Blog.get_post_image(id),
         true <- image.post_id == post.id,
         _ <- delete_uploaded_file(image.url),
         {:ok, _deleted_image} <- Blog.delete_post_image(image) do
      {:noreply,
       socket
       |> assign(:post, Blog.get_post!(post.id))
       |> put_flash(:info, "Image dihapus")}
    else
      _ ->
        {:noreply, put_flash(socket, :error, "Image tidak valid")}
    end
  end

  def handle_event("cancel-upload", %{"ref" => ref, "target" => target}, socket) do
    target_atom =
      case target do
        "thumbnail_image" -> :thumbnail_image
        "attachment" -> :attachment
        "gallery_images" -> :gallery_images
        _ -> nil
      end

    if target_atom do
      {:noreply, cancel_upload(socket, target_atom, ref)}
    else
      {:noreply, socket}
    end
  end

  defp save_post(socket, post_params) do
    params = Map.put_new(post_params, "tag_ids", [])

    case socket.assigns.live_action do
      :new ->
        case Blog.create_post(params) do
          {:ok, post} ->
            case persist_uploads(socket, post) do
              :ok ->
                {:noreply,
                 socket
                 |> put_flash(:info, "Post created successfully")
                 |> push_navigate(to: ~p"/posts")}

              {:error, message} ->
                {:ok, _deleted_post} = Blog.delete_post(post)
                {:noreply, put_flash(socket, :error, message)}
            end

          {:error, changeset} ->
            {:noreply, assign(socket, :form, to_form(changeset))}
        end

      :edit ->
        post = socket.assigns.post

        case Blog.update_post(post, params) do
          {:ok, updated_post} ->
            case persist_uploads(socket, updated_post) do
              :ok ->
                {:noreply,
                 socket
                 |> put_flash(:info, "Post updated successfully")
                 |> push_navigate(to: ~p"/posts")}

              {:error, message} ->
                {:noreply, put_flash(socket, :error, message)}
            end

          {:error, changeset} ->
            {:noreply, assign(socket, :form, to_form(changeset))}
        end
    end
  end

  defp any_uploads_in_progress?(socket) do
    [:thumbnail_image, :attachment, :gallery_images]
    |> Enum.any?(fn key ->
      {_, in_progress_entries} = uploaded_entries(socket, key)
      in_progress_entries != []
    end)
  end

  defp any_upload_errors?(socket) do
    [:thumbnail_image, :attachment, :gallery_images]
    |> Enum.any?(fn key ->
      upload = Map.fetch!(socket.assigns.uploads, key)
      upload_has_errors?(upload)
    end)
  end

  defp persist_uploads(socket, post) do
    with :ok <- ensure_upload_dir(),
         {:ok, thumbnail} <- consume_role_upload(socket, :thumbnail_image, "thumbnail"),
         {:ok, attachment} <- consume_role_upload(socket, :attachment, "attachment"),
         {:ok, cover} <- build_cover_from_thumbnail(thumbnail),
         {:ok, gallery} <- consume_gallery_uploads(socket) do
      replace_single_roles(post, [cover, thumbnail, attachment])

      all_uploads =
        [cover, thumbnail, attachment]
        |> Enum.reject(&is_nil/1)
        |> Kernel.++(gallery)

      all_uploads
      |> Enum.reduce_while(:ok, fn upload, :ok ->
        case Blog.create_post_image(Map.put(upload, :post_id, post.id)) do
          {:ok, _image} -> {:cont, :ok}
          {:error, _changeset} -> {:halt, :error}
        end
      end)
      |> case do
        :ok -> :ok
        :error -> {:error, "Gagal menyimpan metadata upload"}
      end
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp consume_role_upload(socket, upload_key, role) do
    uploaded =
      consume_uploaded_entries(socket, upload_key, fn %{path: path}, entry ->
        case copy_upload(path, entry.client_name, entry.client_type) do
          {:ok, map} -> {:ok, Map.put(map, :role, role)}
          {:error, _reason} -> :error
        end
      end)

    case uploaded do
      [] -> {:ok, nil}
      [file] -> {:ok, file}
      _ -> {:error, "Upload #{role} tidak valid"}
    end
  rescue
    _ -> {:error, "Gagal memproses upload #{role}"}
  end

  defp build_cover_from_thumbnail(nil), do: {:ok, nil}

  defp build_cover_from_thumbnail(thumbnail) do
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

  defp consume_gallery_uploads(socket) do
    uploaded =
      consume_uploaded_entries(socket, :gallery_images, fn %{path: path}, entry ->
        case copy_upload(path, entry.client_name, entry.client_type) do
          {:ok, map} -> {:ok, Map.put(map, :role, "gallery")}
          {:error, _reason} -> :error
        end
      end)

    {:ok, uploaded}
  rescue
    _ -> {:error, "Gagal memproses upload gallery"}
  end

  defp copy_upload(temp_path, client_name, content_type) do
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

  defp normalize_extension("", "image/jpeg"), do: ".jpg"
  defp normalize_extension("", "image/png"), do: ".png"
  defp normalize_extension("", "image/webp"), do: ".webp"
  defp normalize_extension("", _), do: ".bin"
  defp normalize_extension(ext, _), do: ext

  defp replace_single_roles(post, uploads) do
    roles_to_replace =
      uploads
      |> Enum.reject(&is_nil/1)
      |> Enum.map(& &1.role)
      |> Enum.filter(&(&1 in ["cover", "thumbnail", "attachment"]))
      |> Enum.uniq()

    if roles_to_replace != [] do
      existing_images = Blog.list_post_images(post.id)
      images_to_remove = Enum.filter(existing_images, &(&1.role in roles_to_replace))

      Enum.each(images_to_remove, fn image ->
        _ = delete_uploaded_file(image.url)
      end)

      Blog.delete_post_images(post.id, roles_to_replace)
    end
  end

  defp delete_uploaded_file(url) do
    filename = Path.basename(url)
    path = Path.join(upload_dir(), filename)
    File.rm(path)
  end

  defp upload_dir do
    Path.join(Application.app_dir(:appsatu, "priv/static"), "uploads")
  end

  defp ensure_upload_dir do
    case File.mkdir_p(upload_dir()) do
      :ok -> :ok
      {:error, _reason} -> {:error, "Folder upload tidak bisa dibuat"}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <%= case @live_action do %>
        <% :index -> %>
          <section class="space-y-6">
            <div class="rounded-3xl bg-gradient-to-r from-sky-500 via-cyan-500 to-teal-500 p-[1px] shadow-xl">
              <div class="rounded-3xl bg-base-100 p-6 sm:p-8">
                <div class="flex flex-wrap items-center justify-between gap-4">
                  <div>
                    <h1 class="text-3xl font-bold tracking-tight">Posts Dashboard</h1>
                    <p class="mt-1 text-base-content/60">Kelola konten dengan upload gambar real-time.</p>
                  </div>
                  <.button navigate={~p"/posts/new"} class="btn btn-primary rounded-full px-6">
                    <.icon name="hero-plus" class="size-5" /> New Post
                  </.button>
                </div>
              </div>
            </div>

            <div class="overflow-hidden rounded-3xl border border-base-300 bg-base-100 shadow-sm">
              <.table id="posts" rows={@streams.posts} row_click={fn {_id, post} -> JS.navigate(~p"/posts/#{post.id}") end}>
                <:col :let={{_id, post}} label="Post">
                  <div class="flex items-center gap-3">
                    <div class="avatar">
                      <div class="h-14 w-14 rounded-xl ring-1 ring-base-300">
                        <%= if image = Enum.find(post.images || [], &(&1.role == "cover")) do %>
                          <img src={image.url} alt={post.title} class="object-cover" />
                        <% else %>
                          <div class="flex h-full w-full items-center justify-center bg-base-200 text-base-content/40">
                            <.icon name="hero-photo" class="size-6" />
                          </div>
                        <% end %>
                      </div>
                    </div>
                    <div>
                      <p class="line-clamp-1 text-sm font-bold tracking-tight">{post.title}</p>
                      <p class="mt-0.5 line-clamp-2 text-xs leading-relaxed text-base-content/60">{post.body}</p>
                    </div>
                  </div>
                </:col>
                <:col :let={{_id, post}} label="Meta">
                  <div class="space-y-2 text-sm">
                    <div>
                      <span :if={post.category} class="badge badge-primary badge-soft rounded-full text-[10px] font-semibold uppercase tracking-wide">
                        {post.category.name}
                      </span>
                      <span :if={!post.category} class="text-xs text-base-content/50">No category</span>
                    </div>
                    <div class="flex flex-wrap gap-1.5">
                      <span :if={post.tags == []} class="text-xs text-base-content/50">No tags</span>
                      <span
                        :for={tag <- post.tags}
                        class="badge badge-info badge-soft rounded-full px-2 py-0.5 text-[10px] font-semibold uppercase tracking-wide"
                      >
                        {tag.name}
                      </span>
                    </div>
                  </div>
                </:col>
                <:col :let={{_id, post}} label="Status">
                  <span class={[
                    "badge rounded-full",
                    post.published && "badge-success badge-soft",
                    !post.published && "badge-warning badge-soft"
                  ]}>
                    {if post.published, do: "Published", else: "Draft"}
                  </span>
                </:col>
                <:action :let={{_id, post}}>
                  <.link patch={~p"/posts/#{post.id}/edit"} class="link link-primary">Edit</.link>
                </:action>
                <:action :let={{_id, post}}>
                  <button
                    type="button"
                    phx-click="delete"
                    phx-value-id={post.id}
                    data-confirm="Yakin hapus post ini?"
                    class="link link-error"
                  >
                    Delete
                  </button>
                </:action>
              </.table>
            </div>
          </section>

        <% :new -> %>
          <.post_form_section
            title="Create Post"
            subtitle="Buat post dengan thumbnail, gallery, dan attachment. Cover dibuat otomatis dari thumbnail."
            form={@form}
            categories={@categories}
            tags={@tags}
            uploads={@uploads}
            action={:new}
          />

        <% :edit -> %>
          <.post_form_section
            title={"Edit Post ##{@post.id}"}
            subtitle="Perbarui konten, thumbnail, gallery, dan attachment dengan upload progress."
            form={@form}
            categories={@categories}
            tags={@tags}
            uploads={@uploads}
            action={:edit}
            post={@post}
          />

        <% :show -> %>
          <section class="space-y-6">
            <div class="flex items-center justify-between">
              <.button navigate={~p"/posts"} class="btn btn-ghost rounded-full">
                <.icon name="hero-arrow-left" class="size-4" /> Back
              </.button>
              <.button patch={~p"/posts/#{@post.id}/edit"} class="btn btn-primary rounded-full">
                <.icon name="hero-pencil-square" class="size-4" /> Edit
              </.button>
            </div>

            <article class="rounded-3xl border border-base-300 bg-base-100 p-6 shadow-sm sm:p-8">
              <h1 class="text-3xl font-bold tracking-tight sm:text-4xl">{@post.title}</h1>
              <div class="mt-4 rounded-2xl bg-base-200/40 p-4 sm:p-5">
                <p class="whitespace-pre-line text-sm leading-relaxed text-base-content/80 sm:text-base">
                  {@post.body}
                </p>
              </div>

              <div class="mt-6 flex flex-wrap gap-2">
                <span :if={@post.category} class="badge badge-primary badge-soft rounded-full px-3 py-0.5 text-xs font-semibold uppercase tracking-wide">
                  {@post.category.name}
                </span>
                <span :if={!@post.category} class="badge badge-ghost rounded-full px-3 py-0.5 text-xs">
                  No category
                </span>
                <span
                  :for={tag <- @post.tags}
                  class="badge badge-info badge-soft rounded-full px-3 py-0.5 text-xs font-semibold uppercase tracking-wide"
                >
                  {tag.name}
                </span>
              </div>

              <div class="mt-6 grid grid-cols-2 gap-3 sm:grid-cols-4">
                <div :for={image <- @post.images} class="overflow-hidden rounded-2xl border border-base-300">
                  <img src={image.url} alt={image.filename} class="h-28 w-full object-cover" />
                  <div class="px-3 py-2 text-xs font-semibold uppercase tracking-wide text-base-content/60">
                    {image.role}
                  </div>
                </div>
              </div>
            </article>
          </section>
      <% end %>
    </Layouts.app>
    """
  end

  attr :title, :string, required: true
  attr :subtitle, :string, required: true
  attr :form, Phoenix.HTML.Form, required: true
  attr :categories, :list, required: true
  attr :tags, :list, required: true
  attr :uploads, :map, required: true
  attr :action, :atom, required: true
  attr :post, :map, default: nil

  defp post_form_section(assigns) do
    selected_tag_ids = selected_tag_ids(assigns.form)

    assigns =
      assign(assigns, :submit_disabled?, submit_disabled?(assigns.uploads))
      |> assign(:selected_tag_ids, selected_tag_ids)
      |> assign(:selected_tag_count, length(selected_tag_ids))
      |> assign(:body_length, body_length(assigns.form))

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
              <p class="text-xs font-semibold uppercase tracking-wide text-base-content/60">Category</p>
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
              <label
                :for={tag <- @tags}
                class="group cursor-pointer"
              >
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
            <p class="mb-3 text-sm font-semibold uppercase tracking-wide text-base-content/70">Media Upload</p>
            <p class="mb-4 text-xs text-base-content/60">
              Cover image dibuat otomatis dari Thumbnail (versi kecil/compress).
            </p>
            <div class="grid gap-4 md:grid-cols-2">
              <.upload_field upload={@uploads.thumbnail_image} label="Thumbnail Image" target="thumbnail_image" />
              <.upload_field upload={@uploads.attachment} label="Attachment" target="attachment" />
              <.upload_field upload={@uploads.gallery_images} label="Gallery Images" target="gallery_images" />
            </div>
          </div>

          <div :if={@action == :edit && @post && @post.images != []} class="rounded-2xl border border-base-300 p-4">
            <p class="mb-3 text-sm font-semibold uppercase tracking-wide text-base-content/70">Existing Media</p>
            <div class="grid grid-cols-2 gap-3 sm:grid-cols-4">
              <div :for={image <- @post.images} class="overflow-hidden rounded-xl border border-base-300 bg-base-100">
                <img src={image.url} alt={image.filename} class="h-24 w-full object-cover" />
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
            <.button type="submit" disabled={@submit_disabled?} class="btn btn-primary rounded-full px-7">
              <.icon name="hero-check-circle" class="size-5" />
              {if @action == :new, do: "Create Post", else: "Update Post"}
            </.button>
            <.button navigate={~p"/posts"} class="btn btn-ghost rounded-full">Cancel</.button>
          </div>
        </.form>
      </div>
    </section>
    """
  end

  attr :upload, :map, required: true
  attr :label, :string, required: true
  attr :target, :string, required: true

  defp upload_field(assigns) do
    ~H"""
    <div class="space-y-2 rounded-xl border border-base-300 p-3">
      <label class="text-sm font-medium">{@label}</label>
      <div
        phx-drop-target={@upload.ref}
        class="relative rounded-xl border-2 border-dashed border-base-300 bg-base-200/30 p-4 transition hover:border-primary"
      >
        <.live_file_input upload={@upload} class="absolute inset-0 h-full w-full cursor-pointer opacity-0" />
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
              <%= if String.starts_with?(entry.client_type || "", "image/") do %>
                <.live_img_preview entry={entry} class="h-24 w-full object-cover" />
              <% else %>
                <div class="flex h-24 items-center justify-center text-center text-xs text-base-content/60">
                  {entry.client_name}
                </div>
              <% end %>
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

  defp upload_error_to_text(:too_large), do: "Ukuran file terlalu besar (maks 5MB)"
  defp upload_error_to_text(:not_accepted), do: "Tipe file tidak didukung. Gunakan JPG, JPEG, PNG, atau WEBP"
  defp upload_error_to_text(:too_many_files), do: "Jumlah file melebihi batas"
  defp upload_error_to_text(_), do: "Upload gagal"

  defp submit_disabled?(uploads) do
    [:thumbnail_image, :attachment, :gallery_images]
    |> Enum.any?(fn key ->
      upload = Map.fetch!(uploads, key)
      upload_has_errors?(upload) || Enum.any?(upload.entries, &(&1.progress < 100))
    end)
  end

  defp upload_has_errors?(upload) do
    upload_errors(upload) != [] ||
      Enum.any?(upload.entries, fn entry ->
        upload_errors(upload, entry) != []
      end)
  end

  defp selected_tag_ids(form) do
    form[:tag_ids].value
    |> List.wrap()
    |> Enum.map(&to_string/1)
  end

  defp body_length(form) do
    form[:body].value
    |> to_string()
    |> String.length()
  end
end
