defmodule Banter.Conversations.Runner do
  @moduledoc """
  Runs the LLM conversation loop: sends the conversation history to the
  configured provider, streams text deltas, executes tool calls, and
  persists everything as messages.

  A run is normally started with `start/1`, which spawns a supervised,
  unlinked task so the run completes even if the user navigates away.
  `run/2` is the synchronous entry point (used directly in tests).

  Progress is broadcast on the PubSub topic `"conversation:<id>"`:

    * `{:run_started, conversation_id}`
    * `{:llm_delta, text}` - a streamed fragment of the assistant reply
    * `{:message_appended, message}` - a newly persisted message
    * `{:tool_call_started, tool_call}` - about to execute a tool call
    * `{:tool_call_finished, tool_call_id, name, status}` - `status` is `:ok` or `:error`
    * `{:run_finished, conversation_id}`
    * `{:run_failed, conversation_id, reason}`
  """

  alias Banter.{Accounts, Conversations, LLM, Tools}
  alias Banter.Conversations.Conversation

  @pubsub Banter.PubSub
  @max_tool_iterations 8

  @doc """
  Subscribes the calling process to events for the given conversation.
  """
  def subscribe(conversation_id) do
    Phoenix.PubSub.subscribe(@pubsub, topic(conversation_id))
  end

  @doc """
  Unsubscribes the calling process from events for the given conversation.
  """
  def unsubscribe(conversation_id) do
    Phoenix.PubSub.unsubscribe(@pubsub, topic(conversation_id))
  end

  @doc """
  Returns true if a run is currently in progress for the conversation.
  """
  def running?(conversation_id) do
    Registry.lookup(Banter.RunnerRegistry, conversation_id) != []
  end

  @doc """
  Starts a run for the conversation as a supervised background task.

  Returns `{:error, :already_running}` if a run is already in progress.
  """
  def start(conversation_id) do
    if running?(conversation_id) do
      {:error, :already_running}
    else
      Task.Supervisor.start_child(Banter.TaskSupervisor, fn -> run(conversation_id) end)
    end
  end

  @doc """
  Runs the conversation loop synchronously, returning `:ok` or
  `{:error, reason}`.
  """
  def run(conversation_id, opts \\ []) do
    case Registry.register(Banter.RunnerRegistry, conversation_id, nil) do
      {:ok, _} ->
        try do
          do_run(conversation_id, opts)
        after
          Registry.unregister(Banter.RunnerRegistry, conversation_id)
        end

      {:error, {:already_registered, _pid}} ->
        {:error, "a run is already in progress for this conversation"}
    end
  end

  defp do_run(conversation_id, opts) do
    conversation = Conversations.get_conversation!(conversation_id)
    user = Accounts.get_user!(conversation.user_id)
    max_iterations = Keyword.get(opts, :max_tool_iterations, @max_tool_iterations)

    broadcast(conversation.id, {:run_started, conversation.id})

    case check_and_compact(conversation) do
      :ok ->
        case loop(conversation, user, max_iterations) do
          :ok ->
            broadcast(conversation.id, {:run_finished, conversation.id})
            :ok

          {:error, reason} ->
            broadcast(conversation.id, {:run_failed, conversation.id, reason})
            {:error, reason}
        end

      {:error, reason} ->
        broadcast(conversation.id, {:run_failed, conversation.id, reason})
        {:error, reason}
    end
  end

  defp check_and_compact(%Conversation{} = conversation) do
    if Conversations.compaction_needed?(conversation) do
      broadcast(conversation.id, {:compaction_started, conversation.id})

      case Banter.Conversations.Compaction.compact(conversation) do
        :ok ->
          broadcast(conversation.id, {:compaction_finished, conversation.id})
          :ok

        {:error, reason} ->
          {:error, reason}
      end
    else
      :ok
    end
  end

  defp loop(_conversation, _user, 0), do: {:error, "too many tool calls"}

  defp loop(%Conversation{} = conversation, user, iterations_left) do
    messages =
      conversation
      |> Conversations.messages_for_api_with_compaction()
      |> prepend_system_prompt()

    llm_opts = Conversations.llm_opts_for_conversation(conversation)

    with_forwarder(conversation.id, fn stream_to ->
      LLM.chat(
        messages,
        [
          model: conversation.model,
          tools: Tools.enabled_specs(user),
          stream_to: stream_to
        ] ++ llm_opts
      )
    end)
    |> case do
      {:ok, response, usage} ->
        {:ok, message} = persist_assistant_message(conversation, response)
        Conversations.create_message_usage(message, usage)
        broadcast(conversation.id, {:message_appended, message})

        case response["tool_calls"] do
          calls when calls in [nil, []] ->
            :ok

          calls ->
            execute_tool_calls(conversation, user, calls)
            loop(conversation, user, iterations_left - 1)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp persist_assistant_message(conversation, response) do
    Conversations.create_message(conversation, %{
      role: "assistant",
      content: response["content"],
      tool_calls: response["tool_calls"]
    })
  end

  defp execute_tool_calls(conversation, user, tool_calls) do
    Enum.each(tool_calls, fn tool_call ->
      %{"id" => id, "function" => %{"name" => name}} = tool_call

      broadcast(conversation.id, {:tool_call_started, tool_call})

      {status, content} = execute_tool_call(conversation, user, tool_call)

      broadcast(conversation.id, {:tool_call_finished, id, name, status})

      {:ok, message} =
        Conversations.create_message(conversation, %{
          role: "tool",
          tool_call_id: id,
          content: content
        })

      broadcast(conversation.id, {:message_appended, message})
    end)
  end

  defp execute_tool_call(conversation, user, %{
         "function" => %{"name" => name, "arguments" => arguments}
       }) do
    case Jason.decode(arguments || "{}") do
      {:ok, args} when is_map(args) ->
        context = %{conversation: conversation}

        case Tools.execute(user, name, args, context) do
          {:ok, result} -> {:ok, result}
          {:error, reason} -> {:error, "Error: #{reason}"}
        end

      _ ->
        {:error, "Error: could not parse tool arguments"}
    end
  end

  # The standing system prompt. It goes first, ahead of any compaction
  # summaries, so the model's instructions are not diluted by history.
  defp prepend_system_prompt(messages) do
    [%{"role" => "system", "content" => system_prompt_text()} | messages]
  end

  defp system_prompt_text do
    "You are Banter, a helpful assistant. " <>
      "Use the update_conversation_title tool to give the conversation a " <>
      "short, descriptive title once you understand the user's intent, and " <>
      "again if the topic changes. Keep titles under 8 words and do not call " <>
      "the tool more than necessary."
  end

  # Spawns a process that forwards streamed LLM deltas to PubSub, then
  # runs `fun` with the forwarder pid as the `:stream_to` target. On
  # return the forwarder is drained and stopped, so by the time `fun`'s
  # result is available every delta has been broadcast.
  defp with_forwarder(conversation_id, fun) do
    forwarder = spawn_link(fn -> forward_loop(conversation_id) end)

    try do
      fun.(forwarder)
    after
      send(forwarder, :stop)
      ref = Process.monitor(forwarder)

      receive do
        {:DOWN, ^ref, :process, ^forwarder, _reason} -> :ok
      end
    end
  end

  defp forward_loop(conversation_id) do
    receive do
      :stop ->
        :ok

      {:llm_text_delta, chunk} ->
        broadcast(conversation_id, {:llm_delta, chunk})
        forward_loop(conversation_id)
    end
  end

  defp broadcast(conversation_id, event) do
    Phoenix.PubSub.broadcast(@pubsub, topic(conversation_id), event)
  end

  defp topic(conversation_id), do: "conversation:#{conversation_id}"
end
