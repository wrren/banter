defmodule Banter.Conversations.Compaction do
  @moduledoc """
  Handles conversation compaction through summarization.

  When a conversation exceeds the model's context threshold, older messages
  are summarized and replaced with a single summary message to free up
  context space while preserving key information.
  """

  alias Banter.{Accounts, Conversations, LLM}
  alias Banter.Conversations.Conversation

  @summary_portion 0.6
  @min_messages_for_compaction 4

  @doc """
  Compacts a conversation by summarizing older messages.

  Takes approximately the first 60% of non-compacted messages, generates
  a summary using the LLM, and marks those messages as compacted.
  """
  def compact(%Conversation{} = conversation) do
    messages = Conversations.list_active_messages(conversation)

    if length(messages) < @min_messages_for_compaction do
      {:error, "not enough messages to compact"}
    else
      do_compact(conversation, messages)
    end
  end

  defp do_compact(%Conversation{} = conversation, messages) do
    %{context_limit: _context_limit} = model = Conversations.get_conversation_model(conversation)
    target_count = floor(length(messages) * @summary_portion)
    messages_to_compact = Enum.take(messages, target_count)

    prompt = build_summarization_prompt(messages_to_compact)

    user = Accounts.get_user!(conversation.user_id)

    with {:ok, response, _usage} <- call_llm_for_summary(prompt, conversation, user, model),
         summary_content <- Map.get(response, "content", "") || "" do
      message_ids = Enum.map(messages_to_compact, & &1.id)
      token_count = estimate_token_count(summary_content)

      {:ok, _} =
        Conversations.create_compaction_summary(
          conversation,
          summary_content,
          message_ids,
          token_count
        )

      Conversations.mark_messages_compacted(message_ids)

      :ok
    else
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_summarization_prompt(messages) do
    formatted =
      Enum.map_join(messages, "\n", fn msg ->
        "[#{msg.role}]: #{msg.content || "[empty]"}"
      end)

    """
    Summarize the following conversation concisely while preserving all key information, facts, decisions, code examples, URLs, and important details. The summary should capture the essence of what was discussed so far.

    Conversation:
    #{formatted}

    Summary:
    """
  end

  defp call_llm_for_summary(prompt, conversation, _user, _model) do
    messages = [
      %{
        "role" => "system",
        "content" => "You are a helpful assistant that summarizes conversations."
      },
      %{
        "role" => "user",
        "content" => prompt
      }
    ]

    llm_opts = Conversations.llm_opts_for_conversation(conversation)

    forwarder = spawn_link(fn -> forward_deltas() end)

    try do
      LLM.chat(
        messages,
        [
          model: conversation.model,
          tools: [],
          stream_to: forwarder
        ] ++ llm_opts
      )
    after
      send(forwarder, :stop)
    end
  end

  defp forward_deltas do
    receive do
      :stop ->
        :ok

      {:llm_text_delta, _chunk} ->
        forward_deltas()
    end
  end

  defp estimate_token_count(text) do
    div(String.length(text), 4)
  end
end
