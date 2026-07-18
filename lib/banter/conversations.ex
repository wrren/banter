defmodule Banter.Conversations do
  @moduledoc """
  The Conversations context: persistence for conversations and their messages.
  """

  import Ecto.Query, warn: false

  alias Banter.Conversations.{Conversation, Message}
  alias Banter.Repo

  ## Conversations

  @doc """
  Lists a user's conversations, most recently active first.
  """
  def list_conversations(%Banter.Accounts.User{} = user) do
    Repo.all(
      from c in Conversation,
        where: c.user_id == ^user.id,
        order_by: [desc: c.updated_at, desc: c.id]
    )
  end

  @doc """
  Gets a single conversation by id, raising if it does not exist.

  This does not check ownership; use `get_user_conversation!/2` from
  user-facing code paths.
  """
  def get_conversation!(id), do: Repo.get!(Conversation, id)

  @doc """
  Gets a single conversation owned by the given user, raising if it does
  not exist or belongs to someone else.
  """
  def get_user_conversation!(%Banter.Accounts.User{} = user, id) do
    Repo.get_by!(Conversation, id: id, user_id: user.id)
  end

  @doc """
  Creates a conversation for a user. `model` is required in `attrs`.
  """
  def create_conversation(%Banter.Accounts.User{} = user, attrs \\ %{}) do
    %Conversation{user_id: user.id}
    |> Conversation.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a conversation's title and/or model.
  """
  def update_conversation(%Conversation{} = conversation, attrs) do
    conversation
    |> Conversation.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a conversation and all of its messages.
  """
  def delete_conversation(%Conversation{} = conversation) do
    Repo.delete(conversation)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking conversation changes.
  """
  def change_conversation(%Conversation{} = conversation, attrs \\ %{}) do
    Conversation.changeset(conversation, attrs)
  end

  @doc """
  Sets the conversation title from the first user message, if the
  conversation still has the default title.
  """
  def maybe_retitle(%Conversation{title: title} = conversation, text) do
    if title == Conversation.default_title() do
      new_title =
        text
        |> String.replace(~r/\s+/, " ")
        |> String.trim()
        |> String.slice(0, 60)

      if new_title == "" do
        {:ok, conversation}
      else
        update_conversation(conversation, %{title: new_title})
      end
    else
      {:ok, conversation}
    end
  end

  ## Messages

  @doc """
  Lists the messages of a conversation in chronological order.
  """
  def list_messages(%Conversation{} = conversation) do
    Repo.all(
      from m in Message,
        where: m.conversation_id == ^conversation.id,
        order_by: [asc: m.inserted_at, asc: m.id]
    )
  end

  @doc """
  Appends a message to a conversation and bumps the conversation's
  `updated_at` so listing order reflects recent activity.
  """
  def create_message(%Conversation{} = conversation, attrs) do
    %Message{conversation_id: conversation.id}
    |> Message.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, message} ->
        touch_conversation(conversation)
        {:ok, message}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  defp touch_conversation(conversation) do
    conversation
    |> Ecto.Changeset.change()
    |> Repo.update(force: true)
  end

  @doc """
  Converts a list of persisted messages into the OpenAI chat completions
  request shape.
  """
  def messages_for_api(messages) do
    Enum.map(messages, &message_for_api/1)
  end

  defp message_for_api(%Message{} = message) do
    %{"role" => message.role, "content" => message.content}
    |> maybe_put("tool_calls", message.tool_calls)
    |> maybe_put("tool_call_id", message.tool_call_id)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, []), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
