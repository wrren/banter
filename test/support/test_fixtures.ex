defmodule Banter.TestFixtures do
  @moduledoc """
  Shared fixtures for tests.
  """

  alias Banter.{Accounts, Conversations}

  def unique_username do
    "user_#{System.unique_integer([:positive])}"
  end

  def valid_password do
    "correct horse battery staple"
  end

  def valid_user_attributes(attrs \\ %{}) do
    %{
      username: unique_username(),
      password: valid_password()
    }
    |> Map.merge(attrs)
  end

  def user_fixture(attrs \\ %{}) do
    {:ok, user} =
      attrs
      |> valid_user_attributes()
      |> Accounts.register_user()

    user
  end

  def conversation_fixture(user, attrs \\ %{}) do
    attrs = Map.put_new(attrs, :model, "test-model")

    {:ok, conversation} = Conversations.create_conversation(user, attrs)
    conversation
  end
end
