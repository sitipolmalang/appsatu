defmodule Appsatu.Repo.Migrations.CreateTags do
  use Ecto.Migration

  def change do
    create table(:tags) do
      add :name, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:tags, [:name])
  end
end
