defmodule AppsatuWeb.PostLive do
  use AppsatuWeb, :live_view

  require Logger

  # --- Context Aliases ---
  # Memanggil module Blog untuk akses database post, category, tag
  alias Appsatu.Blog
  alias Appsatu.Blog.Post
  alias Appsatu.UploadConfig

  # --- Component & Upload Aliases ---
  # Memanggil components.ex - berisi komponen UI (sidebar, header, form dll)
  alias AppsatuWeb.PostLive.Components
  # Memanggil uploads.ex - berisi helper untuk handle file upload
  alias AppsatuWeb.PostLive.Uploads

  # --- Configuration ---
  # Tipe file yang diizinkan untuk upload
  @allowed_upload_types UploadConfig.allowed_extensions()
  # Ukuran maksimal file upload
  @max_upload_size UploadConfig.max_file_size()
  # Key untuk berbagai jenis upload
  @upload_keys [:cover_image, :thumbnail_image, :attachment, :gallery_images]

  # ============================================================
  # MOUNT - Dipanggil saat LiveView pertama kali di-load
  # ============================================================
  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:categories, Blog.list_categories()) # Ambil list kategori untuk dropdown filter
      |> assign(:tags, Blog.list_tags()) # Ambil list tag untuk form post
      |> assign(:post, nil) # Post yang sedang diedit/ditampilkan (nil untuk index)
      |> assign(:preview_image, nil) # Data untuk image preview modal
      |> assign(:page_title, "Posts") # Judul halaman default
      |> stream(:posts, [], reset: true) # Stream untuk list post, diisi saat handle_params dipanggil
      |> maybe_assign_uploads() # Setup upload configuration jika belum ada

    {:ok, socket}
  end

  # ============================================================
  # UPLOADS - Konfigurasi upload file ke LiveView
  # Dipanggil di mount() untuk enable upload capability
  # ============================================================
  defp maybe_assign_uploads(socket) do
    if socket.assigns[:uploads] do
      socket
    else
      socket
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
        max_entries: UploadConfig.max_gallery_entries(),
        max_file_size: @max_upload_size,
        auto_upload: true
      )
    end
  end

  # ============================================================
  # HANDLE_PARAMS - Handle URL params & live_action (index/new/edit/show)
  # Dipanggil saat URL berubah atau live_action di-trigger
  # ============================================================
  @impl true
  def handle_params(params, _uri, socket) do
    current_user_id = get_current_user_id(socket)

    case socket.assigns.live_action do
        action when action in [nil, :index] ->
          posts = Blog.list_posts()

          {:noreply,
           socket
           |> assign(:page_title, "Posts")
           |> assign(:preview_image, nil)
           |> assign(:current_user_id, current_user_id)
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
           |> assign(:current_user_id, current_user_id)
           |> put_form_assigns(changeset)}

        :edit ->
          post = Blog.get_post!(params["id"])

          if post.user_id == current_user_id do
            changeset =
              post
              |> Blog.change_post()
              |> Ecto.Changeset.put_change(:tag_ids, Enum.map(post.tags, & &1.id))

            {:noreply,
             socket
             |> assign(:page_title, "Edit Post")
             |> assign(:post, post)
             |> assign(:preview_image, nil)
             |> assign(:current_user_id, current_user_id)
             |> put_form_assigns(changeset)}
          else
            {:noreply,
             socket
             |> put_flash(:error, "Anda tidak memiliki akses ke post ini")
             |> push_navigate(to: ~p"/posts")}
          end

        :show ->
          post = Blog.get_post!(params["id"])

           {:noreply,
            socket
            |> assign(:page_title, "Post Detail")
            |> assign(:preview_image, nil)
            |> assign(:post, post)
            |> assign(:current_user_id, current_user_id)}
      end
  end

  # ============================================================
  # HANDLE_EVENT - Handle events dari browser (form, clicks, dll)
  # ============================================================
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

  # --- Simpan post (create/update) ---
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

  # --- Hapus post ---
  def handle_event("delete", %{"id" => id}, socket) do
    current_user_id = get_current_user_id(socket)
    post = Blog.get_post!(id)

    if post.user_id == current_user_id do
      {:ok, _deleted_post} = delete_post_with_uploads(post)

      {:noreply,
       socket
       |> put_flash(:info, "Post deleted")
       |> stream_delete(:posts, post)}
    else
      {:noreply, put_flash(socket, :error, "Anda tidak memiliki akses untuk menghapus post ini")}
    end
  end

  # --- Hapus gambar existing ---
  def handle_event("delete-existing-image", %{"id" => image_id}, socket) do
    post = socket.assigns.post
    current_user_id = get_current_user_id(socket)

    with true <- post.user_id == current_user_id,
         {id, ""} <- Integer.parse(image_id),
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
      false ->
        {:noreply, put_flash(socket, :error, "Anda tidak memiliki akses")}

      _ ->
        {:noreply, put_flash(socket, :error, "Image tidak valid")}
    end
  end

  # --- Preview image ---
  def handle_event(
        "open-image-preview",
        %{"url" => url, "filename" => filename, "role" => role},
        socket
      ) do
    {:noreply, assign(socket, :preview_image, %{url: url, filename: filename, role: role})}
  end

  # --- Close preview ---
  def handle_event("close-image-preview", _params, socket) do
    {:noreply, assign(socket, :preview_image, nil)}
  end

  # --- Cancel upload ---
  def handle_event("cancel-upload", %{"ref" => ref, "target" => target}, socket) do
    target_atom = upload_target(target)

    if target_atom do
      {:noreply, cancel_upload(socket, target_atom, ref)}
    else
      {:noreply, socket}
    end
  end

  # ============================================================
  # SAVE_POST - Logic untuk create/update post
  # Termasuk authorization check sebelum update
  # ============================================================
  defp save_post(socket, post_params) do
    params = Map.put_new(post_params, "tag_ids", [])
    user_id = get_current_user_id(socket)

    case socket.assigns.live_action do
      :new ->
        case Blog.create_post(Map.put(params, "user_id", user_id)) do
          {:ok, post} ->
            case persist_uploads(socket, post) do
              :ok ->
                {:noreply,
                 socket
                 |> put_flash(:info, "Post created successfully")
                 |> push_navigate(to: ~p"/posts")}

              {:error, message} ->
                {:ok, _deleted_post} = delete_post_with_uploads(post)
                {:noreply, put_flash(socket, :error, message)}
            end

          {:error, changeset} ->
            {:noreply, put_form_assigns(socket, changeset)}
        end

      :edit ->
        post = socket.assigns.post

        if post.user_id == user_id do
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
        else
          {:noreply,
           socket
           |> put_flash(:error, "Anda tidak memiliki akses untuk mengedit post ini")
           |> push_navigate(to: ~p"/posts")}
        end
    end
  end

  # ============================================================
  # UPLOAD HELPERS - Pengecekan dan proses upload
  # ============================================================

  # --- Cek apakah ada upload yang masih berjalan ---
  defp any_uploads_in_progress?(socket) do
    @upload_keys
    |> Enum.any?(fn key ->
      {_, in_progress_entries} = uploaded_entries(socket, key)
      in_progress_entries != []
    end)
  end

  # --- Cek apakah ada upload yang error ---
  defp any_upload_errors?(socket) do
    @upload_keys
    |> Enum.any?(fn key ->
      upload = Map.fetch!(socket.assigns.uploads, key)
      upload_has_errors?(upload)
    end)
  end

  # ============================================================
  # PERSIST UPLOADS - Simpan file upload ke database
  # Setelah post berhasil dibuat/diupdate
  # ============================================================
  defp persist_uploads(socket, post) do
    with {:ok, cover} <- consume_role_upload(socket, :cover_image, "cover", post),
         {:ok, thumbnail} <- consume_role_upload(socket, :thumbnail_image, "thumbnail", post),
         {:ok, attachment} <- consume_role_upload(socket, :attachment, "attachment", post),
         {:ok, gallery} <- consume_gallery_uploads(socket, post) do
      existing_single_role_images = replaceable_images(post, [cover, thumbnail, attachment])

      all_uploads =
        [cover, thumbnail, attachment]
        |> Enum.reject(&is_nil/1)
        |> Kernel.++(gallery)

      all_uploads
      |> Enum.reduce_while(:ok, fn upload, :ok ->
        case Blog.create_post_image(Map.put(upload, :post_id, post.id)) do
          {:ok, _image} -> {:cont, :ok}
          {:error, changeset} -> {:halt, {:error, changeset}}
        end
      end)
      |> case do
        :ok ->
          cleanup_replaced_images(existing_single_role_images)

        {:error, changeset} ->
          {:error, "Gagal menyimpan metadata upload: #{first_changeset_error(changeset)}"}
      end
    else
      {:error, reason} -> {:error, reason}
    end
  end

  # --- Ambil error message pertama dari changeset ---
  defp first_changeset_error(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, _opts} -> msg end)
    |> Enum.find_value("validasi gagal", fn {_field, messages} ->
      List.first(messages)
    end)
  end

  # --- Consume single role upload (cover/thumbnail/attachment) ---
  # Memanggil Uploads.prepare_upload_attrs() untuk proses file
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
    e in [File.Error, Ecto.Query.CompileError] ->
      Logger.error("Upload failed for #{role}: #{inspect(e, pretty: true)}")
      {:error, "Gagal memproses upload #{role}"}

    e ->
      Logger.error("Unexpected error during upload for #{role}: #{inspect(e, pretty: true)}")
      {:error, "Gagal memproses upload #{role}"}
  end

  # --- Consume gallery uploads (multiple images) ---
  defp consume_gallery_uploads(socket, post) do
    uploaded =
      consume_uploaded_entries(socket, :gallery_images, fn %{path: path}, entry ->
        case Uploads.prepare_upload_attrs(
               path,
               entry.client_name,
               entry.client_type,
               post,
               "gallery"
             ) do
          {:ok, map} -> {:ok, map}
          {:error, _reason} -> :error
        end
      end)

    {:ok, uploaded}
  rescue
    e in [File.Error, Ecto.Query.CompileError] ->
      Logger.error("Upload failed for gallery: #{inspect(e, pretty: true)}")
      {:error, "Gagal memproses upload gallery"}

    e ->
      Logger.error("Unexpected error during gallery upload: #{inspect(e, pretty: true)}")
      {:error, "Gagal memproses upload gallery"}
  end

  # ============================================================
  # IMAGE MANAGEMENT - Replace & cleanup
  # ============================================================

  # --- Cari gambar yang bisa di-replace (jika upload baru ada ---
  defp replaceable_images(post, uploads) do
    roles_to_replace =
      uploads
      |> Enum.reject(&is_nil/1)
      |> Enum.map(& &1.role)
      |> Enum.filter(&(&1 in ["cover", "thumbnail", "attachment"]))
      |> Enum.uniq()

    existing_images = Blog.list_post_images(post.id)
    Enum.filter(existing_images, &(&1.role in roles_to_replace))
  end

  # --- Hapus gambar lama yang di-replace ---
  defp cleanup_replaced_images(images) do
    ids = Enum.map(images, & &1.id)
    _ = Blog.delete_post_images_by_ids(ids)

    Enum.each(images, fn image ->
      _ = Uploads.delete_uploaded_file(image)
    end)

    :ok
  end

  # --- Hapus post beserta semua gambarnya ---
  defp delete_post_with_uploads(post) do
    existing_images = Blog.list_post_images(post.id)

    with {:ok, deleted_post} <- Blog.delete_post(post) do
      Enum.each(existing_images, fn image ->
        _ = Uploads.delete_uploaded_file(image)
      end)

      {:ok, deleted_post}
    end
  end

  # ============================================================
  # FORM HELPERS - Untuk render form di template
  # ============================================================

  # --- Cek apakah form bisa di-submit ---
  defp submit_disabled?(uploads) do
    @upload_keys
    |> Enum.any?(fn key ->
      upload = Map.fetch!(uploads, key)
      upload_has_errors?(upload) || Enum.any?(upload.entries, &(&1.progress < 100))
    end)
  end

  # --- Mapping string target ke atom key ---
  defp upload_target(target) do
    case target do
      "cover_image" -> :cover_image
      "thumbnail_image" -> :thumbnail_image
      "attachment" -> :attachment
      "gallery_images" -> :gallery_images
      _ -> nil
    end
  end

  # --- Cek apakah ada error di upload ---
  defp upload_has_errors?(upload) do
    upload_errors(upload) != [] ||
      Enum.any?(upload.entries, fn entry ->
        upload_errors(upload, entry) != []
      end)
  end

  # ============================================================
  # FORM & UTILITY HELPERS
  # ============================================================

  # --- Siapkan assigns untuk form rendering ---
  defp put_form_assigns(socket, changeset) do
    form = to_form(changeset)
    selected_tag_ids = selected_tag_ids(form)

    socket
    |> assign(:form, form)
    |> assign(:selected_tag_ids, selected_tag_ids)
    |> assign(:selected_tag_count, length(selected_tag_ids))
    |> assign(:body_length, body_length(form))
  end

  # --- Ambil ID tags yang dipilih dari form ---
  defp selected_tag_ids(form) do
    form[:tag_ids].value
    |> List.wrap()
    |> Enum.map(&to_string/1)
  end

  # --- Hitung panjang body text ---
  defp body_length(form) do
    form[:body].value
    |> to_string()
    |> String.length()
  end

  # ============================================================
  # IMAGE HELPERS
  # ============================================================

  # --- Ambil filename dari image struct ---
  defp filename_label(%{file_name: file_name}) when is_binary(file_name), do: file_name
  defp filename_label(file_name) when is_binary(file_name), do: file_name
  defp filename_label(_), do: "uploaded-file"

  # --- Bangun URL untuk image ---
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

  # ============================================================
  # USER HELPERS - Ambil user ID dari socket
  # ============================================================

  # Ambil user_id dari current_scope (di-set oleh UserAuth plug)
  defp get_current_user_id(socket) do
    case socket.assigns do
      %{current_scope: %{user: %{id: user_id}}} -> user_id
      _ -> nil
    end
  end
end
