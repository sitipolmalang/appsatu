defmodule AppsatuWeb.PostLive do
  use AppsatuWeb, :live_view

  alias Appsatu.Blog
  alias Appsatu.Blog.Post
  alias AppsatuWeb.PostLive.Components
  alias AppsatuWeb.PostLive.Uploads

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
      |> assign(:preview_image, nil)
      |> assign(:page_title, "Posts")
      |> stream(:posts, [])
      |> allow_upload(:cover_image,
        accept: @allowed_upload_types,
        max_entries: 1,
        max_file_size: @max_upload_size,
        auto_upload: true
      )
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
         |> assign(:preview_image, nil)
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
         |> assign(:preview_image, nil)
         |> put_form_assigns(changeset)}

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
         |> assign(:preview_image, nil)
         |> put_form_assigns(changeset)}

      :show ->
        post = Blog.get_post!(params["id"])

        {:noreply,
         socket
         |> assign(:page_title, "Post Detail")
         |> assign(:preview_image, nil)
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

    {:noreply, put_form_assigns(socket, changeset)}
  end

  def handle_event("save", %{"post" => post_params}, socket) do
    cond do
      any_uploads_in_progress?(socket) ->
        {:noreply, put_flash(socket, :error, "Upload masih berjalan, tunggu sampai selesai")}

      any_upload_errors?(socket) ->
        {:noreply, put_flash(socket, :error, "Masih ada file upload yang tidak valid")}

      true ->
        save_post(socket, post_params)
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
         _ <- Uploads.delete_uploaded_file(image),
         {:ok, _deleted_image} <- Blog.delete_post_image(image) do
      {:noreply,
       socket
       |> assign(:post, Blog.get_post!(post.id))
       |> assign(:preview_image, nil)
       |> put_flash(:info, "Image dihapus")}
    else
      _ ->
        {:noreply, put_flash(socket, :error, "Image tidak valid")}
    end
  end

  def handle_event("open-image-preview", %{"url" => url, "filename" => filename, "role" => role}, socket) do
    {:noreply, assign(socket, :preview_image, %{url: url, filename: filename, role: role})}
  end

  def handle_event("close-image-preview", _params, socket) do
    {:noreply, assign(socket, :preview_image, nil)}
  end

  def handle_event("cancel-upload", %{"ref" => ref, "target" => target}, socket) do
    target_atom =
      case target do
        "cover_image" -> :cover_image
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
            {:noreply, put_form_assigns(socket, changeset)}
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
            {:noreply, put_form_assigns(socket, changeset)}
        end
    end
  end

  defp any_uploads_in_progress?(socket) do
    [:cover_image, :thumbnail_image, :attachment, :gallery_images]
    |> Enum.any?(fn key ->
      {_, in_progress_entries} = uploaded_entries(socket, key)
      in_progress_entries != []
    end)
  end

  defp any_upload_errors?(socket) do
    [:cover_image, :thumbnail_image, :attachment, :gallery_images]
    |> Enum.any?(fn key ->
      upload = Map.fetch!(socket.assigns.uploads, key)
      upload_has_errors?(upload)
    end)
  end

  defp persist_uploads(socket, post) do
    with :ok <- Uploads.ensure_upload_dir(),
         {:ok, cover} <- consume_role_upload(socket, :cover_image, "cover", post),
         {:ok, thumbnail} <- consume_role_upload(socket, :thumbnail_image, "thumbnail", post),
         {:ok, attachment} <- consume_role_upload(socket, :attachment, "attachment", post),
         {:ok, gallery} <- consume_gallery_uploads(socket, post) do
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

  defp consume_role_upload(socket, upload_key, role, post) do
    uploaded =
      consume_uploaded_entries(socket, upload_key, fn %{path: path}, entry ->
        case Uploads.prepare_upload_attrs(path, entry.client_name, entry.client_type, post, role) do
          {:ok, map} -> {:ok, map}
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

  defp consume_gallery_uploads(socket, post) do
    uploaded =
      consume_uploaded_entries(socket, :gallery_images, fn %{path: path}, entry ->
        case Uploads.prepare_upload_attrs(path, entry.client_name, entry.client_type, post, "gallery") do
          {:ok, map} -> {:ok, map}
          {:error, _reason} -> :error
        end
      end)

    {:ok, uploaded}
  rescue
    _ -> {:error, "Gagal memproses upload gallery"}
  end

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
        _ = Uploads.delete_uploaded_file(image)
      end)

      Blog.delete_post_images(post.id, roles_to_replace)
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
              <.table
                id="posts"
                rows={@streams.posts}
                row_click={fn {_id, post} -> JS.navigate(~p"/posts/#{post.id}") end}
              >
                <:col :let={{_id, post}} label="Post">
                  <div class="flex items-center gap-3">
                    <div class="avatar">
                      <div class="h-14 w-14 rounded-xl ring-1 ring-base-300">
                        <%= if image = Enum.find(post.images || [], &(&1.role == "cover")) do %>
                          <img src={image_url(image)} alt={post.title} class="object-cover" />
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
                      <span
                        :if={post.category}
                        class="badge badge-primary badge-soft rounded-full text-[10px] font-semibold uppercase tracking-wide"
                      >
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
          <Components.post_form_section
            title="Create Post"
            subtitle="Buat post dengan cover, thumbnail, gallery, dan attachment."
            form={@form}
            categories={@categories}
            tags={@tags}
            uploads={@uploads}
            action={:new}
            preview_image={@preview_image}
            submit_disabled={submit_disabled?(@uploads)}
            selected_tag_ids={@selected_tag_ids}
            selected_tag_count={@selected_tag_count}
            body_length={@body_length}
          />

        <% :edit -> %>
          <Components.post_form_section
            title={"Edit Post ##{@post.id}"}
            subtitle="Perbarui konten, thumbnail, gallery, dan attachment dengan upload progress."
            form={@form}
            categories={@categories}
            tags={@tags}
            uploads={@uploads}
            action={:edit}
            post={@post}
            preview_image={@preview_image}
            submit_disabled={submit_disabled?(@uploads)}
            selected_tag_ids={@selected_tag_ids}
            selected_tag_count={@selected_tag_count}
            body_length={@body_length}
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
                <span
                  :if={@post.category}
                  class="badge badge-primary badge-soft rounded-full px-3 py-0.5 text-xs font-semibold uppercase tracking-wide"
                >
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
                        class="h-28 w-full object-cover transition duration-200 group-hover:scale-[1.02] group-hover:opacity-90"
                      />
                      <div class="pointer-events-none absolute inset-0 flex items-center justify-center bg-black/0 transition group-hover:bg-black/25">
                        <span class="rounded-full border border-white/50 bg-black/35 px-2 py-1 text-[10px] font-semibold uppercase tracking-wide text-white opacity-0 transition group-hover:opacity-100">
                          preview
                        </span>
                      </div>
                    </div>
                  </button>
                  <div class="px-3 py-2 text-xs font-semibold uppercase tracking-wide text-base-content/60">
                    {image.role}
                  </div>
                </div>
              </div>
            </article>
          </section>
      <% end %>

      <Components.image_preview_modal preview_image={@preview_image} />
    </Layouts.app>
    """
  end

  defp submit_disabled?(uploads) do
    [:cover_image, :thumbnail_image, :attachment, :gallery_images]
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

  defp put_form_assigns(socket, changeset) do
    form = to_form(changeset)
    selected_tag_ids = selected_tag_ids(form)

    socket
    |> assign(:form, form)
    |> assign(:selected_tag_ids, selected_tag_ids)
    |> assign(:selected_tag_count, length(selected_tag_ids))
    |> assign(:body_length, body_length(form))
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

  defp filename_label(%{file_name: file_name}) when is_binary(file_name), do: file_name
  defp filename_label(file_name) when is_binary(file_name), do: file_name
  defp filename_label(_), do: "uploaded-file"

  defp image_url(image) do
    case filename_label(image.filename) do
      "uploaded-file" ->
        image.url

      file_name ->
        "/uploads/posts/#{image.post_id}/#{image.role}/#{file_name}"
    end
  end
end
