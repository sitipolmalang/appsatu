# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     Appsatu.Repo.insert!(%Appsatu.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

alias Appsatu.Blog.Category
alias Appsatu.Blog.Tag
alias Appsatu.Repo

category_names = [
  "Technology",
  "Business",
  "Lifestyle",
  "Education",
  "Travel"
]

tag_names = [
  "elixir",
  "phoenix",
  "ecto",
  "liveview",
  "tutorial"
]

Enum.each(category_names, fn name ->
  Repo.insert!(
    %Category{name: name},
    on_conflict: :nothing,
    conflict_target: :name
  )
end)

Enum.each(tag_names, fn name ->
  Repo.insert!(
    %Tag{name: name},
    on_conflict: :nothing,
    conflict_target: :name
  )
end)
