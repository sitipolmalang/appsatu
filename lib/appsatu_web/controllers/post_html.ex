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
  attr :tags, :list, default: []

  def post_form(assigns)

  def image_label(%{file_name: file_name}) when is_binary(file_name), do: file_name
  def image_label(file_name) when is_binary(file_name), do: file_name
  def image_label(_), do: "uploaded-file"

  def image_url(image) do
    case image_label(image.filename) do
      "uploaded-file" ->
        image.url

      file_name ->
        "/uploads/posts/#{image.post_id}/#{image.role}/#{file_name}"
    end
  end
end
