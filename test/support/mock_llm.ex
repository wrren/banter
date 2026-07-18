defmodule Banter.LLM.Mock do
  @moduledoc """
  A scripted mock LLM provider for tests.

  The mock is backed by a global agent (started in `test_helper.exs`), so
  tests that use it must run with `async: false`.

  ## Scripting responses

      Banter.LLM.Mock.set_script([
        {:text, "Hello there!"},
        {:tool_call, "web_search", %{"query" => "elixir"}},
        {:error, "boom"}
      ])

  Each call to `chat/2` pops the next scripted response:

    * `{:text, text}` - streams `text` to the `:stream_to` pid in small
      chunks (like the real provider) and returns it as the assistant
      message content
    * `{:tool_call, name, args}` - returns an assistant message with an
      OpenAI-shaped tool call (`args` is JSON-encoded)
    * `{:error, reason}` - returns `{:error, reason}`

  Use `calls/0` to inspect the messages and options the mock received.
  """

  @behaviour Banter.LLM.Provider

  @name __MODULE__

  def start do
    Agent.start(fn -> %{script: [], calls: []} end, name: @name)
  end

  @doc "Replaces the response script and clears recorded calls."
  def set_script(script) when is_list(script) do
    Agent.update(@name, fn _state -> %{script: script, calls: []} end)
  end

  @doc "Returns the list of recorded calls, oldest first."
  def calls do
    @name |> Agent.get(& &1.calls) |> Enum.reverse()
  end

  @impl true
  def chat(messages, opts) do
    record_call(messages, opts)

    case next_response() do
      nil ->
        {:error, "Banter.LLM.Mock: no scripted response"}

      {:text, text} ->
        stream_text(text, Keyword.get(opts, :stream_to))
        {:ok, %{"role" => "assistant", "content" => text, "tool_calls" => nil}}

      {:tool_call, name, args} ->
        {:ok,
         %{
           "role" => "assistant",
           "content" => nil,
           "tool_calls" => [build_tool_call(name, args)]
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp record_call(messages, opts) do
    call = %{
      messages: messages,
      model: Keyword.get(opts, :model),
      tools: Keyword.get(opts, :tools, [])
    }

    Agent.update(@name, fn state -> %{state | calls: [call | state.calls]} end)
  end

  defp next_response do
    Agent.get_and_update(@name, fn state ->
      case state.script do
        [response | rest] -> {response, %{state | script: rest}}
        [] -> {nil, state}
      end
    end)
  end

  defp stream_text(_text, nil), do: :ok

  defp stream_text(text, pid) do
    text
    |> String.graphemes()
    |> Enum.chunk_every(4)
    |> Enum.map(&Enum.join/1)
    |> Enum.each(fn chunk -> send(pid, {:llm_text_delta, chunk}) end)
  end

  defp build_tool_call(name, args) do
    %{
      "id" => "call_#{System.unique_integer([:positive])}",
      "type" => "function",
      "function" => %{"name" => name, "arguments" => Jason.encode!(args)}
    }
  end
end
