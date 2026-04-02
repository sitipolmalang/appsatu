defmodule Appsatu.Repo.Migrations.CreatePosts do
  use Ecto.Migration

  def change do
    create table(:posts) do
      add :title, :string
      add :body, :text
      add :published, :boolean, default: false, null: false

      timestamps(type: :utc_datetime)
    end
  end
end
