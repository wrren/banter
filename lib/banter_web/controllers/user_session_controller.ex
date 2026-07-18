defmodule BanterWeb.UserSessionController do
  @moduledoc """
  Handles session actions that require a real connection: registration,
  login and logout.
  """
  use BanterWeb, :controller

  alias Banter.Accounts
  alias BanterWeb.UserAuth

  @doc "POST /users/register — create an account and start a session."
  def register(conn, %{"user" => user_params}) do
    case Accounts.register_user(user_params) do
      {:ok, user} ->
        conn
        |> put_flash(:info, "Account created successfully. Welcome!")
        |> UserAuth.log_in_user(user)

      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_flash(:error, registration_error(changeset))
        |> redirect(to: ~p"/users/register")
    end
  end

  @doc "POST /users/log-in — verify credentials and start a session."
  def create(conn, %{"user" => %{"username" => username, "password" => password}}) do
    if user = Accounts.get_user_by_username_and_password(username, password) do
      conn
      |> put_flash(:info, "Welcome back, #{user.username}!")
      |> UserAuth.log_in_user(user)
    else
      # keep the error generic to avoid leaking which usernames exist
      conn
      |> put_flash(:error, "Invalid username or password")
      |> redirect(to: ~p"/users/log-in")
    end
  end

  @doc "DELETE /users/log-out — end the session."
  def delete(conn, _params) do
    conn
    |> put_flash(:info, "Logged out successfully.")
    |> UserAuth.log_out_user()
  end

  defp registration_error(changeset) do
    "Could not create account: " <>
      (changeset
       |> Ecto.Changeset.traverse_errors(fn {message, opts} ->
         Regex.replace(~r"%{(\w+)}", message, fn _, key ->
           opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
         end)
       end)
       |> Enum.map_join(", ", fn {field, messages} -> "#{field} #{Enum.join(messages, ", ")}" end))
  end
end
