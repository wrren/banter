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

  ## Usage Tracking

  alias Banter.Conversations.{MessageUsage, CompactionMessage}

  @doc """
  Creates message usage record from API response.
  """
  def create_message_usage(%Message{} = message, usage) do
    %MessageUsage{
      message_id: message.id,
      conversation_id: message.conversation_id,
      prompt_tokens: Map.get(usage, :prompt_tokens, 0),
      completion_tokens: Map.get(usage, :completion_tokens, 0),
      total_tokens: Map.get(usage, :total_tokens, 0)
    }
    |> Repo.insert()
  end

  @doc """
  Gets total token usage for a conversation, excluding compacted messages.
  """
  def total_active_usage(%Conversation{} = conversation) do
    result =
      Repo.one!(
        from u in MessageUsage,
          join: m in assoc(u, :message),
          where: m.conversation_id == ^conversation.id and m.is_compacted == false,
          select: %{
            prompt_tokens: sum(u.prompt_tokens),
            completion_tokens: sum(u.completion_tokens),
            total_tokens: sum(u.total_tokens)
          }
      )

    %{
      prompt_tokens: result.prompt_tokens || 0,
      completion_tokens: result.completion_tokens || 0,
      total_tokens: result.total_tokens || 0
    }
  end

  @doc """
  Gets total token usage for a conversation including all tokens (including compacted).
  """
  def total_usage(%Conversation{} = conversation) do
    result =
      Repo.one!(
        from u in MessageUsage,
          where: u.conversation_id == ^conversation.id,
          select: %{
            prompt_tokens: sum(u.prompt_tokens),
            completion_tokens: sum(u.completion_tokens),
            total_tokens: sum(u.total_tokens)
          }
      )

    %{
      prompt_tokens: result.prompt_tokens || 0,
      completion_tokens: result.completion_tokens || 0,
      total_tokens: result.total_tokens || 0
    }
  end

  @doc """
  Gets the conversation's active model metadata.
  """
  def get_conversation_model(%Conversation{} = conversation) do
    if conversation.llm_model_id do
      Repo.get(Banter.Providers.Model, conversation.llm_model_id)
    else
      nil
    end
  end

  @doc """
  Gets the conversation's active provider.
  """
  def get_conversation_provider(%Conversation{} = conversation) do
    if conversation.provider_id do
      Repo.get(Banter.Providers.Provider, conversation.provider_id)
    else
      nil
    end
  end

  @doc """
  Returns the extra LLM options (`:base_url`, `:api_key`) needed to route
  a conversation's requests through its database-backed provider. Returns
  an empty list for conversations using the globally configured provider.
  """
  def llm_opts_for_conversation(%Conversation{} = conversation) do
    case get_conversation_provider(conversation) do
      nil ->
        []

      provider ->
        [
          base_url: provider.base_url,
          api_key: Banter.Providers.decrypt_api_key(provider)
        ]
    end
  end

  @doc """
  Checks if compaction is needed based on current usage and model context limit.
  """
  def compaction_needed?(%Conversation{} = conversation) do
    with %{context_limit: context_limit, compaction_threshold: threshold} <-
           get_conversation_model(conversation),
         usage <- total_active_usage(conversation),
         threshold_tokens <- floor(context_limit * Decimal.to_float(threshold)) do
      usage.total_tokens >= threshold_tokens
    else
      _ -> false
    end
  end

  ## Compaction

  @doc """
  Lists non-compacted messages in a conversation.
  """
  def list_active_messages(%Conversation{} = conversation) do
    Repo.all(
      from m in Message,
        where: m.conversation_id == ^conversation.id and m.is_compacted == false,
        order_by: [asc: m.inserted_at, asc: m.id]
    )
  end

  @doc """
  Marks messages as compacted.
  """
  def mark_messages_compacted(message_ids) when is_list(message_ids) do
    Repo.update_all(
      from(m in Message, where: m.id in ^message_ids),
      set: [is_compacted: true, updated_at: DateTime.utc_now()]
    )
  end

  @doc """
  Creates a compaction summary record.
  """
  def create_compaction_summary(
        %Conversation{} = conversation,
        summary_content,
        original_message_ids,
        token_count
      ) do
    %CompactionMessage{
      conversation_id: conversation.id,
      summary_content: summary_content,
      original_message_ids: original_message_ids,
      token_count: token_count
    }
    |> Repo.insert()
  end

  @doc """
  Gets all compaction summaries for a conversation, ordered chronologically.
  """
  def list_compaction_summaries(%Conversation{} = conversation) do
    Repo.all(
      from c in CompactionMessage,
        where: c.conversation_id == ^conversation.id,
        order_by: [asc: c.inserted_at, asc: c.id]
    )
  end

  @doc """
  Builds messages for API including compaction summaries as context.
  """
  def messages_for_api_with_compaction(%Conversation{} = conversation) do
    summaries = list_compaction_summaries(conversation)
    active_messages = list_active_messages(conversation)

    messages =
      Enum.flat_map(summaries, fn summary ->
        [
          %{
            "role" => "system",
            "content" => "Previous conversation summary: #{summary.summary_content}"
          }
        ]
      end) ++ messages_for_api(active_messages)

    messages
  end
end
