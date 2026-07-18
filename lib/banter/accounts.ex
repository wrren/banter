defmodule Banter.Accounts do
  @moduledoc """
  The Accounts context: registration, authentication, and sessions.
  """

  import Ecto.Query, warn: false

  alias Banter.Accounts.{User, UserToken}
  alias Banter.Repo

  ## Registration

  @doc """
  Registers a user with a username and password.
  """
  def register_user(attrs) do
    %User{}
    |> User.registration_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking user registration changes.
  """
  def change_user_registration(%User{} = user, attrs \\ %{}) do
    User.registration_changeset(user, attrs, hash_password: false)
  end

  ## Authentication

  @doc """
  Gets a single user by id, raising if it does not exist.
  """
  def get_user!(id), do: Repo.get!(User, id)

  @doc """
  Gets a user by username.
  """
  def get_user_by_username(username) when is_binary(username) do
    Repo.get_by(User, username: username)
  end

  @doc """
  Gets a user by username and password, verifying the password.
  """
  def get_user_by_username_and_password(username, password)
      when is_binary(username) and is_binary(password) do
    user = get_user_by_username(username)
    if User.valid_password?(user, password), do: user
  end

  @doc """
  Changes a user's password, requiring the current password to match.
  """
  def change_user_password(%User{} = user, attrs \\ %{}) do
    User.password_changeset(user, attrs, hash_password: false)
  end

  @doc """
  Updates a user's password after validating the current password.

  Returns `{:ok, user}` or `{:error, changeset}`. On success, all of the
  user's other session tokens are deleted (the caller is responsible for
  keeping or renewing the current session).
  """
  def update_user_password(%User{} = user, current_password, attrs) do
    if User.valid_password?(user, current_password) do
      user
      |> User.password_changeset(attrs)
      |> Repo.update()
      |> case do
        {:ok, user} = ok ->
          # invalidate all other sessions
          Repo.delete_all(UserToken.by_user_and_contexts_query(user, :all))
          ok

        {:error, changeset} ->
          {:error, changeset}
      end
    else
      {:error,
       user
       |> User.password_changeset(attrs)
       |> Ecto.Changeset.add_error(:current_password, "is not correct")
       |> Map.put(:action, :validate)}
    end
  end

  ## Sessions

  @doc """
  Generates a session token for a user and persists it.
  """
  def generate_user_session_token(user) do
    {token, user_token} = UserToken.build_session_token(user)
    Repo.insert!(user_token)
    token
  end

  @doc """
  Gets the user with the given signed session token, or nil if the token
  is invalid or expired.
  """
  def fetch_user_by_session_token(token) do
    case UserToken.verify_session_token_query(token) do
      {:ok, user} -> {:ok, user}
      :error -> :error
    end
  end

  @doc """
  Deletes the signed session token, effectively logging the user out.
  """
  def delete_user_session_token(token) do
    Repo.delete_all(UserToken.by_token_and_context_query(token, "session"))
    :ok
  end
end
