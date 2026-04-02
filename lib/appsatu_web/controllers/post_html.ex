defmodule AppsatuWeb.PostHTML do
  use AppsatuWeb, :html

  embed_templates "post_html/*"

  @doc """
  Renders a post form.

  The form is defined in the template at
  post_html/post_form.html.heex
  """
  attr :changeset, Ecto.Changeset, required: true
  attr :action, :string, required: true
  attr :return_to, :string, default: nil
  attr :categories, :list, default: []

  def post_form(assigns)
end
