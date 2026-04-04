defmodule Appsatu.Blog.PostImage do
  use Ecto.Schema
  import Ecto.Changeset

  @roles ~w(cover thumbnail gallery attachment)

  schema "post_images" do
    field :role, :string
    field :url, :string
    field :filename, :string
    field :content_type, :string
    field :size, :integer

    belongs_to :post, Appsatu.Blog.Post

    timestamps(type: :utc_datetime)
  end

  def changeset(post_image, attrs) do
    post_image
    |> cast(attrs, [:post_id, :role, :url, :filename, :content_type, :size])
    |> validate_required([:post_id, :role, :url, :filename, :content_type, :size])
    |> validate_inclusion(:role, @roles)
    |> validate_number(:size, greater_than: 0)
    |> foreign_key_constraint(:post_id)
  end
end
