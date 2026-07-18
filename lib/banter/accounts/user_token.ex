defmodule Banter.Accounts.UserToken do
  @moduledoc """
  Persists session tokens (stored SHA256-hashed) for signed-in users.
  """
  use Ecto.Schema

  import Ecto.Query, warn: false

  @rand_size 32
  @hash_algorithm :sha256

  @session_validity_in_days 60

  schema "user_tokens" do
    field :token, :binary
    field :context, :string

    belongs_to :user, Banter.Accounts.User

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc """
  Generates a token that will be stored in a signed place, such as the
  session. The token itself is returned; only its SHA256 digest is
  persisted.
  """
  def build_session_token(user) do
    token = :crypto.strong_rand_bytes(@rand_size)
    {token, %__MODULE__{token: hash_token(token), context: "session", user_id: user.id}}
  end

  defp hash_token(token) do
    :crypto.hash(@hash_algorithm, token)
  end

  @doc """
  Returns the user for the given session token, if the token is valid
  and not expired.
  """
  def verify_session_token_query(token) do
    query =
      from token in by_token_and_context(token, "session"),
        join: user in assoc(token, :user),
        where: token.inserted_at > ago(@session_validity_in_days, "day"),
        select: user

    case Banter.Repo.one(query) do
      nil -> :error
      user -> {:ok, user}
    end
  end

  defp by_token_and_context(token, context) do
    from t in __MODULE__, where: t.token == ^hash_token(token) and t.context == ^context
  end

  @doc """
  Returns the query for deleting a single token by value and context.
  """
  def by_token_and_context_query(token, context) do
    by_token_and_context(token, context)
  end

  @doc """
  Returns the query for deleting all tokens of a user with the given
  context (`:all` for every token).
  """
  def by_user_and_contexts_query(user, :all) do
    from t in __MODULE__, where: t.user_id == ^user.id
  end

  def by_user_and_contexts_query(user, context) do
    from t in __MODULE__, where: t.user_id == ^user.id and t.context == ^context
  end
end
