defmodule AppsatuWeb.TagHTML do
  use AppsatuWeb, :html

  embed_templates "tag_html/*"

  @doc """
  Renders a tag form.

  The form is defined in the template at
  tag_html/tag_form.html.heex
  """
  attr :changeset, Ecto.Changeset, required: true
  attr :action, :string, required: true
  attr :return_to, :string, default: nil

  def tag_form(assigns)
end
