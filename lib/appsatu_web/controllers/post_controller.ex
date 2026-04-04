defmodule AppsatuWeb.PostController do
  use AppsatuWeb, :controller

  alias Appsatu.Blog
  alias Appsatu.Blog.Post
  alias AppsatuWeb.PostLive.Uploads

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
        {:ok, _deleted_post} = delete_post_with_uploads(post)

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
    {:ok, _post} = delete_post_with_uploads(post)

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
         {:ok, prepared} <- Uploads.prepare_upload_from_plug(upload, role) do
      {:ok, prepared}
    else
      {:error, reason} when is_binary(reason) ->
        {:error, :upload, reason}

      other ->
        other
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

  defp persist_uploads(_post, []), do: :ok

  defp persist_uploads(post, uploads) do
    existing_single_role_images = replaceable_images(post, uploads)

    uploads
    |> Enum.reduce_while(:ok, fn upload, :ok ->
      upload
      |> Map.put(:post_id, post.id)
      |> Blog.create_post_image()
      |> case do
        {:ok, _post_image} -> {:cont, :ok}
        {:error, _changeset} -> {:halt, :error}
      end
    end)
    |> case do
      :ok ->
        cleanup_replaced_images(existing_single_role_images)

      :error -> {:error, :persist_upload, post}
    end
  end

  defp replaceable_images(post, uploads) do
    roles_to_replace =
      uploads
      |> Enum.map(& &1.role)
      |> Enum.uniq()
      |> Enum.filter(&(&1 in ["cover", "thumbnail", "attachment"]))

    existing_images = Blog.list_post_images(post.id)
    Enum.filter(existing_images, &(&1.role in roles_to_replace))
  end

  defp cleanup_replaced_images(images) do
    ids = Enum.map(images, & &1.id)
    _ = Blog.delete_post_images_by_ids(ids)

    Enum.each(images, fn image ->
      _ = Uploads.delete_uploaded_file(image)
    end)

    :ok
  end

  defp delete_post_with_uploads(post) do
    existing_images = Blog.list_post_images(post.id)

    with {:ok, deleted_post} <- Blog.delete_post(post) do
      Enum.each(existing_images, fn image ->
        _ = Uploads.delete_uploaded_file(image)
      end)

      {:ok, deleted_post}
    end
  end

  defp upload_size(path) do
    case File.stat(path) do
      {:ok, %{size: size}} -> size
      _ -> 0
    end
  end
end
