defmodule Appsatu.Blog.PostImage do
  use Ecto.Schema
  use Waffle.Ecto.Schema
  import Ecto.Changeset

  alias Appsatu.Uploaders.PostImage, as: PostImageUploader

  @roles ~w(cover thumbnail gallery attachment)

  schema "post_images" do
    field :role, :string
    field :url, :string
    field :filename, PostImageUploader.Type
    field :content_type, :string
    field :size, :integer

    belongs_to :post, Appsatu.Blog.Post

    timestamps(type: :utc_datetime)
  end

  def changeset(post_image, attrs) do
    post_image
    |> cast(attrs, [:post_id, :role, :url, :content_type, :size])
    |> cast_attachments(attrs, [:filename])
    |> maybe_put_url()
    |> validate_required([:post_id, :role, :url, :filename, :content_type, :size])
    |> validate_inclusion(:role, @roles)
    |> validate_number(:size, greater_than: 0)
    |> foreign_key_constraint(:post_id)
  end

  defp maybe_put_url(changeset) do
    scope = Ecto.Changeset.apply_changes(changeset)
    filename = Ecto.Changeset.get_field(changeset, :filename)

    case filename do
      nil ->
        changeset

      %{file_name: file_name} when is_binary(file_name) ->
        put_change(changeset, :url, "/uploads/posts/#{scope.post_id}/#{scope.role}/#{file_name}")

      file_name when is_binary(file_name) ->
        put_change(changeset, :url, "/uploads/posts/#{scope.post_id}/#{scope.role}/#{file_name}")

      _ ->
        changeset
    end
  end
end
