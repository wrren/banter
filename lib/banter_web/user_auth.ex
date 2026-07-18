defmodule BanterWeb.UserAuth do
  @moduledoc """
  Authentication plugs and LiveView on_mount hooks.

  Session state is a single `"user_token"` session value, created on
  login and verified against the (hashed) tokens persisted by
  `Banter.Accounts`.
  """
  use BanterWeb, :verified_routes

  import Plug.Conn
  import Phoenix.Controller

  alias Banter.Accounts
  alias Banter.Accounts.Scope

  ## Plugs

  @doc """
  Fetches the current `Banter.Accounts.Scope` from the session token and
  assigns it as `:current_scope` (nil when signed out).
  """
  def fetch_current_scope(conn, _opts) do
    conn
    |> assign(:current_scope, scope_from_session(conn))
  end

  @doc """
  Requires an authenticated user, redirecting to the login page otherwise.
  """
  def require_authenticated_user(conn, _opts) do
    if conn.assigns[:current_scope] && conn.assigns.current_scope.user do
      conn
    else
      conn
      |> put_flash(:error, "You must log in to access this page.")
      |> redirect(to: ~p"/users/log-in")
      |> halt()
    end
  end

  @doc """
  Redirects already-authenticated users to the home page.
  """
  def redirect_if_authenticated(conn, _opts) do
    if conn.assigns[:current_scope] && conn.assigns.current_scope.user do
      conn
      |> redirect(to: ~p"/")
      |> halt()
    else
      conn
    end
  end

  ## Login / logout

  @doc """
  Logs the user in: generates a session token, renews the session (to
  avoid fixation), and redirects home.
  """
  def log_in_user(conn, user) do
    token = Accounts.generate_user_session_token(user)

    conn
    |> renew_session()
    |> put_session("user_token", token)
    |> redirect(to: ~p"/")
  end

  @doc """
  Logs the user out: deletes the session token and clears the session.
  """
  def log_out_user(conn) do
    if token = get_session(conn, "user_token") do
      Accounts.delete_user_session_token(token)
    end

    conn
    |> renew_session()
    |> redirect(to: ~p"/users/log-in")
  end

  defp renew_session(conn) do
    conn
    |> configure_session(renew: true)
    |> clear_session()
  end

  ## LiveView on_mount hooks

  def on_mount(:mount_current_scope, _params, session, socket) do
    {:cont, mount_current_scope(socket, session)}
  end

  def on_mount(:ensure_authenticated, _params, session, socket) do
    socket = mount_current_scope(socket, session)

    if socket.assigns.current_scope && socket.assigns.current_scope.user do
      {:cont, socket}
    else
      {:halt,
       socket
       |> Phoenix.LiveView.put_flash(:error, "You must log in to access this page.")
       |> Phoenix.LiveView.redirect(to: ~p"/users/log-in")}
    end
  end

  def on_mount(:redirect_if_authenticated, _params, session, socket) do
    socket = mount_current_scope(socket, session)

    if socket.assigns.current_scope && socket.assigns.current_scope.user do
      {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/")}
    else
      {:cont, socket}
    end
  end

  defp mount_current_scope(socket, session) do
    Phoenix.Component.assign_new(socket, :current_scope, fn ->
      scope_from_session(session)
    end)
  end

  defp scope_from_session(%Plug.Conn{} = conn) do
    conn |> get_session("user_token") |> scope_from_token()
  end

  defp scope_from_session(session) when is_map(session) do
    session |> Map.get("user_token") |> scope_from_token()
  end

  defp scope_from_token(token) when is_binary(token) do
    case Accounts.fetch_user_by_session_token(token) do
      {:ok, user} -> Scope.for_user(user)
      :error -> nil
    end
  end

  defp scope_from_token(_), do: nil
end
