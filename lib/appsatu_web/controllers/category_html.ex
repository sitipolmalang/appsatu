defmodule AppsatuWeb.CategoryHTML do
  use AppsatuWeb, :html

  embed_templates "category_html/*"

  @doc """
  Renders a category form.

  The form is defined in the template at
  category_html/category_form.html.heex
  """
  attr :changeset, Ecto.Changeset, required: true
  attr :action, :string, required: true
  attr :return_to, :string, default: nil

  def category_form(assigns)
end
