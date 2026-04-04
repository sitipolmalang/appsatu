
defmodule Appsatu.Repo.Migrations.CreatePostImages do
  use Ecto.Migration

  def change do
    create table(:post_images) do
      add :post_id, references(:posts, on_delete: :delete_all), null: false
      add :role, :string, null: false
      add :url, :string, null: false
      add :filename, :string, null: false
      add :content_type, :string, null: false
      add :size, :integer, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:post_images, [:post_id])
    create index(:post_images, [:role])
    create index(:post_images, [:post_id, :role])
  end
end
