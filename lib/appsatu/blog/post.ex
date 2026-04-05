defmodule Appsatu.Blog.Post do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  schema "posts" do
    field(:title, :string)
    field(:body, :string)
    field(:published, :boolean, default: false)
    field(:tag_ids, {:array, :id}, virtual: true)

    belongs_to(:user, Appsatu.Accounts.User)
    belongs_to(:category, Appsatu.Blog.Category)

    many_to_many(:tags, Appsatu.Blog.Tag,
      join_through: "posts_tags",
      on_replace: :delete
    )

    has_many(:images, Appsatu.Blog.PostImage)

    timestamps(type: :utc_datetime)
  end

  def changeset(post, attrs) do
    post
    |> cast(attrs, [:title, :body, :published, :category_id, :user_id, :tag_ids])
    |> validate_required([:title, :body, :published, :category_id])
    |> foreign_key_constraint(:category_id)
    |> foreign_key_constraint(:user_id)
    |> maybe_put_tags(attrs)
  end

  defp maybe_put_tags(changeset, attrs) do
    case Map.get(attrs, "tag_ids") || Map.get(attrs, :tag_ids) do
      ids when is_list(ids) ->
        put_assoc(changeset, :tags, tags_from_ids(ids))

      _ ->
        changeset
    end
  end

  defp tags_from_ids(tag_ids) do
    ids =
      tag_ids
      |> Enum.map(fn
        id when is_integer(id) -> id
        id when is_binary(id) and id != "" -> String.to_integer(id)
        _ -> nil
      end)
      |> Enum.reject(&is_nil/1)

    Appsatu.Repo.all(from(t in Appsatu.Blog.Tag, where: t.id in ^ids))
  end
end
