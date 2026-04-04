defmodule AppsatuWeb.PostController do
  use AppsatuWeb, :controller

  alias Appsatu.Blog
  alias Appsatu.Blog.Post

  @allowed_content_types ~w(image/jpeg image/png image/webp)
  @max_upload_size 5 * 1024 * 1024

  def index(conn, _params) do
    posts = Blog.list_posts()

    render(conn, :index, posts: posts)
  end

  def new(conn, _params) do
    render_post_form(conn, :new, Blog.change_post(%Post{}))
  end

  def create(conn, %{"post" => post_params}) do
    sanitized_post_params = Map.put_new(post_params, "tag_ids", [])
    upload_params = collect_upload_params(post_params)

    with {:ok, uploads} <- prepare_uploads(upload_params),
         {:ok, post} <- Blog.create_post(sanitized_post_params),
         :ok <- persist_uploads(post, uploads) do
      conn
      |> put_flash(:info, "Post created successfully.")
      |> redirect(to: ~p"/posts/#{post}")
    else
      {:error, :upload, error_message} ->
        changeset =
          %Post{}
          |> Blog.change_post(sanitized_post_params)
          |> Ecto.Changeset.add_error(:title, error_message)

        render_post_form(conn, :new, changeset)

      {:error, %Ecto.Changeset{} = changeset} ->
        render_post_form(conn, :new, changeset)

      {:error, :persist_upload, post} ->
        {:ok, _deleted_post} = Blog.delete_post(post)

        changeset =
          %Post{}
          |> Blog.change_post(sanitized_post_params)
          |> Ecto.Changeset.add_error(:title, "Upload file gagal disimpan")

        render_post_form(conn, :new, changeset)
    end
  end

  def show(conn, %{"id" => id}) do
    post = Blog.get_post!(id)
    render(conn, :show, post: post)
  end

  def edit(conn, %{"id" => id}) do
    post = Blog.get_post!(id)
    changeset = Blog.change_post(post)
    changeset = Ecto.Changeset.put_change(changeset, :tag_ids, Enum.map(post.tags, & &1.id))

    render(conn, :edit,
      post: post,
      changeset: changeset,
      categories: Blog.list_categories(),
      tags: Blog.list_tags()
    )
  end

  def update(conn, %{"id" => id, "post" => post_params}) do
    post = Blog.get_post!(id)
    sanitized_post_params = Map.put_new(post_params, "tag_ids", [])
    upload_params = collect_upload_params(post_params)

    with {:ok, uploads} <- prepare_uploads(upload_params),
         {:ok, updated_post} <- Blog.update_post(post, sanitized_post_params),
         :ok <- persist_uploads(updated_post, uploads) do
      conn
      |> put_flash(:info, "Post updated successfully.")
      |> redirect(to: ~p"/posts/#{updated_post}")
    else
      {:error, :upload, error_message} ->
        changeset =
          post
          |> Blog.change_post(sanitized_post_params)
          |> Ecto.Changeset.add_error(:title, error_message)

        render(conn, :edit,
          post: post,
          changeset: changeset,
          categories: Blog.list_categories(),
          tags: Blog.list_tags()
        )

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, :edit,
          post: post,
          changeset: changeset,
          categories: Blog.list_categories(),
          tags: Blog.list_tags()
        )

      {:error, :persist_upload, _updated_post} ->
        changeset =
          post
          |> Blog.change_post(sanitized_post_params)
          |> Ecto.Changeset.add_error(:title, "Upload file gagal disimpan")

        render(conn, :edit,
          post: post,
          changeset: changeset,
          categories: Blog.list_categories(),
          tags: Blog.list_tags()
        )
    end
  end

  def delete(conn, %{"id" => id}) do
    post = Blog.get_post!(id)
    {:ok, _post} = Blog.delete_post(post)

    conn
    |> put_flash(:info, "Post deleted successfully.")
    |> redirect(to: ~p"/posts")
  end

  defp render_post_form(conn, template, changeset) do
    render(conn, template,
      changeset: changeset,
      categories: Blog.list_categories(),
      tags: Blog.list_tags()
    )
  end

  defp collect_upload_params(post_params) do
    %{
      "cover" => Map.get(post_params, "cover_image"),
      "thumbnail" => Map.get(post_params, "thumbnail_image"),
      "attachment" => Map.get(post_params, "attachment"),
      "gallery" => List.wrap(Map.get(post_params, "gallery_images"))
    }
  end

  defp prepare_uploads(upload_params) do
    with {:ok, cover} <- prepare_optional_upload(Map.get(upload_params, "cover"), "cover"),
         {:ok, thumbnail} <- prepare_optional_upload(Map.get(upload_params, "thumbnail"), "thumbnail"),
         {:ok, attachment} <- prepare_optional_upload(Map.get(upload_params, "attachment"), "attachment"),
         {:ok, gallery} <- prepare_gallery_uploads(Map.get(upload_params, "gallery", [])) do
      {:ok, Enum.reject([cover, thumbnail, attachment] ++ gallery, &is_nil/1)}
    end
  end

  defp prepare_gallery_uploads(uploads) do
    uploads
    |> Enum.reject(&(is_nil(&1) or &1 == ""))
    |> Enum.reduce_while({:ok, []}, fn upload, {:ok, prepared} ->
      case prepare_optional_upload(upload, "gallery") do
        {:ok, nil} -> {:cont, {:ok, prepared}}
        {:ok, value} -> {:cont, {:ok, [value | prepared]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, prepared} -> {:ok, Enum.reverse(prepared)}
      error -> error
    end
  end

  defp prepare_optional_upload(nil, _role), do: {:ok, nil}
  defp prepare_optional_upload("", _role), do: {:ok, nil}

  defp prepare_optional_upload(%Plug.Upload{} = upload, role) do
    with :ok <- validate_upload(upload),
         {:ok, unique_filename} <- build_unique_filename(upload),
         {:ok, relative_url} <- build_relative_url(unique_filename) do
      {:ok,
       %{
         role: role,
         upload: upload,
         filename: unique_filename,
         url: relative_url,
         content_type: upload.content_type,
         size: upload_size(upload.path)
       }}
    end
  end

  defp prepare_optional_upload(_invalid, role) do
    {:error, :upload, "Format upload #{role} tidak valid"}
  end

  defp validate_upload(%Plug.Upload{} = upload) do
    cond do
      upload.content_type not in @allowed_content_types ->
        {:error, :upload, "Tipe file #{upload.content_type} tidak didukung"}

      upload_size(upload.path) > @max_upload_size ->
        {:error, :upload, "Ukuran file melebihi batas maksimum 5 MB"}

      true ->
        :ok
    end
  end

  defp build_unique_filename(%Plug.Upload{} = upload) do
    extension =
      upload.filename
      |> Path.extname()
      |> String.downcase()

    final_extension =
      if extension == "" do
        extension_from_content_type(upload.content_type)
      else
        extension
      end

    case final_extension do
      nil -> {:error, :upload, "Ekstensi file tidak dikenali"}
      ext -> {:ok, Ecto.UUID.generate() <> ext}
    end
  end

  defp build_relative_url(unique_filename) do
    {:ok, "/uploads/" <> unique_filename}
  end

  defp extension_from_content_type("image/jpeg"), do: ".jpg"
  defp extension_from_content_type("image/png"), do: ".png"
  defp extension_from_content_type("image/webp"), do: ".webp"
  defp extension_from_content_type(_), do: nil

  defp persist_uploads(_post, []), do: :ok

  defp persist_uploads(post, uploads) do
    replace_single_roles(post, uploads)

    uploads
    |> Enum.reduce_while(:ok, fn upload, :ok ->
      case copy_and_save_upload(post, upload) do
        :ok -> {:cont, :ok}
        :error -> {:halt, :error}
      end
    end)
    |> case do
      :ok -> :ok
      :error -> {:error, :persist_upload, post}
    end
  end

  defp replace_single_roles(post, uploads) do
    roles_to_replace =
      uploads
      |> Enum.map(& &1.role)
      |> Enum.uniq()
      |> Enum.filter(&(&1 in ["cover", "thumbnail", "attachment"]))

    existing_images = Blog.list_post_images(post.id)
    images_to_remove = Enum.filter(existing_images, &(&1.role in roles_to_replace))

    Enum.each(images_to_remove, fn image ->
      delete_uploaded_file(image.url)
    end)

    Blog.delete_post_images(post.id, roles_to_replace)
  end

  defp copy_and_save_upload(post, upload_data) do
    with :ok <- ensure_upload_dir(),
         :ok <- File.cp(upload_data.upload.path, upload_disk_path(upload_data.filename)),
         {:ok, _post_image} <-
           Blog.create_post_image(%{
             post_id: post.id,
             role: upload_data.role,
             url: upload_data.url,
             filename: upload_data.filename,
             content_type: upload_data.content_type,
             size: upload_data.size
           }) do
      :ok
    else
      _ -> :error
    end
  end

  defp upload_disk_path(filename) do
    Path.join(upload_dir(), filename)
  end

  defp upload_dir do
    Path.join(Application.app_dir(:appsatu, "priv/static"), "uploads")
  end

  defp ensure_upload_dir do
    File.mkdir_p(upload_dir())
  end

  defp upload_size(path) do
    case File.stat(path) do
      {:ok, %{size: size}} -> size
      _ -> 0
    end
  end

  defp delete_uploaded_file(url) do
    filename = Path.basename(url)
    path = upload_disk_path(filename)
    _ = File.rm(path)
    :ok
  end
end
