defmodule Appsatu.Repo.Migrations.AddAltTextAndCaptionToPostImages do
  use Ecto.Migration

  def change do
    alter table(:post_images) do
      add :alt_text, :string
      add :caption, :string
    end
  end
end
