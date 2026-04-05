defmodule AppsatuWeb.Router do
  use AppsatuWeb, :router

  import AppsatuWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {AppsatuWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", AppsatuWeb do
    pipe_through :browser

    get "/", PageController, :home

    live_session :current_user,
      on_mount: [{AppsatuWeb.UserAuth, :mount_current_scope}] do
      live "/users/register", UserLive.Registration, :new
      live "/users/log-in", UserLive.Login, :new
      live "/users/log-in/:token", UserLive.Confirmation, :new

    end

    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete
  end

  scope "/", AppsatuWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated_user,
      on_mount: [{AppsatuWeb.UserAuth, :require_authenticated}] do
      live "/posts/new", PostLive, :new
      live "/posts/:id/edit", PostLive, :edit
      live "/posts/:id", PostLive, :show
      live "/posts", PostLive, :index


      resources "/categories", CategoryController
      resources "/tags", TagController

      live "/users/settings", UserLive.Settings, :edit
      live "/users/settings/confirm-email/:token", UserLive.Settings, :confirm_email

      post "/users/update-password", UserSessionController, :update_password
    end
  end

  if Application.compile_env(:appsatu, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: AppsatuWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
