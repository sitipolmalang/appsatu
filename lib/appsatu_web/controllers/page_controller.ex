defmodule AppsatuWeb.PageController do
  use AppsatuWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
