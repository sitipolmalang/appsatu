defmodule AppsatuWeb.PostControllerTest do
  use AppsatuWeb.ConnCase

  alias Appsatu.Blog
  import Appsatu.BlogFixtures

  @invalid_attrs %{title: nil, body: nil, published: nil, category_id: nil}

  describe "index" do
    test "lists all posts", %{conn: conn} do
      conn = get(conn, ~p"/posts")
      assert html_response(conn, 200) =~ "Listing Posts"
    end
  end

  describe "new post" do
    test "renders form", %{conn: conn} do
      conn = get(conn, ~p"/posts/new")
      assert html_response(conn, 200) =~ "New Post"
    end
  end

  describe "create post" do
    test "redirects to show when data is valid", %{conn: conn} do
      category = category_fixture()

      create_attrs = %{
        title: "some title",
        body: "some body",
        published: true,
        category_id: category.id
      }

      conn = post(conn, ~p"/posts", post: create_attrs)

      assert %{id: id} = redirected_params(conn)
      assert redirected_to(conn) == ~p"/posts/#{id}"

      conn = get(conn, ~p"/posts/#{id}")
      assert html_response(conn, 200) =~ "Post #{id}"
    end

    test "renders errors when data is invalid", %{conn: conn} do
      conn = post(conn, ~p"/posts", post: @invalid_attrs)
      assert html_response(conn, 200) =~ "New Post"
    end
  end

  describe "edit post" do
    setup [:create_post]

    test "renders form for editing chosen post", %{conn: conn, post: post} do
      conn = get(conn, ~p"/posts/#{post}/edit")
      assert html_response(conn, 200) =~ "Edit Post"
    end
  end

  describe "update post" do
    setup [:create_post]

    test "redirects when data is valid", %{conn: conn, post: post} do
      category = category_fixture()

      update_attrs = %{
        title: "some updated title",
        body: "some updated body",
        published: false,
        category_id: category.id
      }

      conn = put(conn, ~p"/posts/#{post}", post: update_attrs)
      assert redirected_to(conn) == ~p"/posts/#{post}"

      conn = get(conn, ~p"/posts/#{post}")
      assert html_response(conn, 200) =~ "some updated title"
    end

    test "renders errors when data is invalid", %{conn: conn, post: post} do
      conn = put(conn, ~p"/posts/#{post}", post: @invalid_attrs)
      assert html_response(conn, 200) =~ "Edit Post"
    end
  end

  describe "delete post" do
    setup [:create_post]

    test "deletes chosen post", %{conn: conn, post: post} do
      conn = delete(conn, ~p"/posts/#{post}")
      assert redirected_to(conn) == ~p"/posts"

      assert_error_sent 404, fn ->
        get(conn, ~p"/posts/#{post}")
      end
    end

    test "deletes uploaded files from storage", %{conn: conn, post: post} do
      {:ok, image} = create_cover_image(post)
      image_path = storage_path(image.url)
      assert File.exists?(image_path)

      conn = delete(conn, ~p"/posts/#{post}")
      assert redirected_to(conn) == ~p"/posts"

      refute File.exists?(image_path)
      assert Blog.list_post_images(post.id) == []
    end
  end

  describe "update post with upload failure" do
    setup [:create_post]

    test "keeps existing cover when new upload is invalid", %{conn: conn, post: post} do
      {:ok, old_cover} = create_cover_image(post)
      old_cover_path = storage_path(old_cover.url)
      assert File.exists?(old_cover_path)

      invalid_upload =
        temp_upload("invalid-cover.jpg", "image/jpeg", "this-is-not-a-jpeg")

      update_attrs = %{
        title: "keep existing cover",
        body: "invalid upload should not replace",
        published: true,
        category_id: post.category_id,
        cover_image: invalid_upload
      }

      conn = put(conn, ~p"/posts/#{post}", post: update_attrs)
      assert html_response(conn, 200) =~ "Edit Post"

      reloaded_images = Blog.list_post_images(post.id)
      assert Enum.any?(reloaded_images, &(&1.id == old_cover.id))
      assert File.exists?(old_cover_path)
    end
  end

  defp create_post(_) do
    post = post_fixture()

    %{post: post}
  end

  defp create_cover_image(post) do
    jpeg_binary = <<0xFF, 0xD8, 0xFF, 0xE0, "JFIF", 0x00, 0x01, 0x02, 0x03>>

    Blog.create_post_image(%{
      post_id: post.id,
      role: "cover",
      filename: %{filename: "cover.jpg", binary: jpeg_binary},
      content_type: "image/jpeg",
      size: byte_size(jpeg_binary)
    })
  end

  defp storage_path(url) when is_binary(url) do
    Path.join(Application.app_dir(:appsatu, "priv/static"), String.trim_leading(url, "/"))
  end

  defp temp_upload(filename, content_type, binary_content) do
    temp_dir = Path.join(File.cwd!(), ".tmp")
    _ = File.mkdir_p(temp_dir)
    temp_path = Path.join(temp_dir, "#{System.unique_integer([:positive])}-#{filename}")
    :ok = File.write(temp_path, binary_content)

    %Plug.Upload{
      path: temp_path,
      filename: filename,
      content_type: content_type
    }
  end
end
