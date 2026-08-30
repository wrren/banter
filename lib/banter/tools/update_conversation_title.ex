defmodule Banter.Tools.UpdateConversationTitle do
  @moduledoc """
  A tool that lets the LLM set the title of the current conversation.

  The Runner passes the active conversation in the execution context
  (`%{conversation: conversation}`), so the context-aware `execute/2`
  callback persists the new title via `Banter.Conversations.update_conversation/2`.
  The plain `execute/1` callback validates the title but performs no write,
  which keeps the tool usable in tests and in contexts without a conversation.
  """
  @behaviour Banter.Tools.Tool

  alias Banter.Conversations

  @max_title_length 120

  @impl true
  def name, do: "update_conversation_title"

  @impl true
  def hidden?, do: true

  @impl true
  def description do
    "Sets the title of the current conversation. Use it early in the " <>
      "conversation once you understand the user's intent, and again if " <>
      "the topic changes, so the conversation has a short, descriptive name."
  end

  @impl true
  def parameters do
    %{
      "type" => "object",
      "properties" => %{
        "title" => %{
          "type" => "string",
          "description" => "A short, descriptive title for the conversation (max 120 characters)."
        }
      },
      "required" => ["title"]
    }
  end

  @impl true
  def execute(%{"title" => title}) when is_binary(title) do
    with :ok <- validate(title) do
      {:ok, "Conversation title set to: #{String.trim(title)}"}
    end
  end

  def execute(_args), do: {:error, "missing required argument: title"}

  @doc """
  Context-aware execution: persists the new title on the conversation
  supplied in the context map.
  """
  @impl true
  def execute(%{"title" => title}, %{conversation: conversation})
      when is_binary(title) do
    with :ok <- validate(title),
         {:ok, _} <- Conversations.update_conversation(conversation, %{title: String.trim(title)}) do
      {:ok, "Conversation title set to: #{String.trim(title)}"}
    end
  end

  def execute(%{"title" => _title}, _context),
    do: {:error, "missing required argument: title"}

  def execute(_args, _context), do: {:error, "missing required argument: title"}

  defp validate(title) do
    trimmed = String.trim(title)

    cond do
      trimmed == "" ->
        {:error, "title must not be empty"}

      String.length(trimmed) > @max_title_length ->
        {:error,
         "title must be at most #{@max_title_length} characters (got #{String.length(trimmed)})"}

      true ->
        :ok
    end
  end
end
