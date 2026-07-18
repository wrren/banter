defmodule BanterWeb.Router do
  use BanterWeb, :router

  import BanterWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {BanterWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", BanterWeb do
    pipe_through :browser

    delete "/users/log-out", UserSessionController, :delete
    post "/users/log-in", UserSessionController, :create
    post "/users/register", UserSessionController, :register

    live_session :redirect_if_authenticated,
      on_mount: [{BanterWeb.UserAuth, :redirect_if_authenticated}] do
      live "/users/register", RegistrationLive
      live "/users/log-in", LoginLive
    end

    live_session :require_authenticated_user,
      on_mount: [{BanterWeb.UserAuth, :ensure_authenticated}] do
      live "/", ChatLive, :index
      live "/c/:id", ChatLive, :show
      live "/users/settings", SettingsLive
    end
  end

  # Other scopes may use custom stacks.
  # scope "/api", BanterWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:banter, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: BanterWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
