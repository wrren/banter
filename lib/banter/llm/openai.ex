defmodule Banter.LLM.OpenAI do
  @moduledoc """
  An LLM provider for OpenAI-compatible chat completions APIs.

  Works with OpenRouter (the default), llama.cpp, vLLM, and other
  endpoints that implement `POST /chat/completions` with server-sent
  event streaming. Configure in `config/runtime.exs` via the
  `LLM_BASE_URL`, `LLM_API_KEY`, `LLM_MODEL` and `LLM_MODELS` environment
  variables.

  Per-call `:base_url` and `:api_key` options override the application
  config, which is how database-backed providers (`Banter.Providers`)
  are routed.
  """
  @behaviour Banter.LLM.Provider

  alias Banter.LLM.SSE

  @impl true
  def chat(messages, opts) do
    model = Keyword.get(opts, :model) || config(:model)
    stream_to = Keyword.get(opts, :stream_to)

    if is_nil(model) do
      {:error, "no model configured: set LLM_MODEL or pass the :model option"}
    else
      {:ok, acc} = Agent.start_link(fn -> initial_state() end)

      try do
        messages
        |> request_body(model, Keyword.get(opts, :tools, []))
        |> post(acc, stream_to, opts)
      after
        Agent.stop(acc)
      end
    end
  end

  defp request_body(messages, model, tools) do
    body = %{"model" => model, "messages" => messages, "stream" => true}

    case tools do
      [] -> body
      nil -> body
      tools -> Map.put(body, "tools", tools)
    end
  end

  defp post(body, acc, stream_to, opts) do
    on_data = fn {:data, chunk}, {req, resp} ->
      process_chunk(acc, stream_to, chunk)
      {:cont, {req, resp}}
    end

    [
      base_url: Keyword.get(opts, :base_url) || config(:base_url),
      url: "/chat/completions",
      json: body,
      into: on_data,
      headers: headers(opts),
      retry: false,
      receive_timeout: config(:receive_timeout) || 120_000
    ]
    |> Keyword.merge(req_options())
    |> Req.new()
    |> Req.post()
    |> case do
      {:ok, %{status: status}} when status in 200..299 ->
        state = Agent.get(acc, fn x -> x end)
        result = build_result(state)

        case result do
          {message, usage} -> {:ok, message, usage}
        end

      {:ok, %{status: status}} ->
        {:error, "LLM request failed (HTTP #{status}): #{error_detail(acc)}"}

      {:error, exception} ->
        {:error, "LLM request failed: #{Exception.message(exception)}"}
    end
  end

  defp headers(opts) do
    case Keyword.get(opts, :api_key) || config(:api_key) do
      nil -> []
      "" -> []
      key -> [{"authorization", "Bearer #{key}"}]
    end
  end

  ## Streaming accumulation

  defp initial_state do
    %{buffer: "", raw: "", content: "", tool_calls: %{}, usage: nil}
  end

  defp process_chunk(acc, stream_to, chunk) do
    events =
      Agent.get_and_update(acc, fn state ->
        {events, rest} = SSE.feed(state.buffer, chunk)
        {events, %{state | buffer: rest, raw: state.raw <> chunk}}
      end)

    Enum.each(events, &handle_event(acc, stream_to, &1))
  end

  defp handle_event(_acc, _stream_to, "[DONE]"), do: :ok

  defp handle_event(acc, stream_to, event) do
    with {:ok, decoded} <- Jason.decode(event) do
      if Map.has_key?(decoded, "usage") do
        handle_usage(acc, decoded["usage"])
      end

      if Map.has_key?(decoded, "choices") do
        case decoded do
          %{"choices" => [%{"delta" => delta} | _]} ->
            handle_delta(acc, stream_to, delta)

          _ ->
            :ok
        end
      else
        :ok
      end
    else
      _ -> :ok
    end
  end

  defp handle_usage(acc, usage) do
    prompt_tokens = usage["prompt_tokens"] || usage["prompt_tokens"] || 0
    completion_tokens = usage["completion_tokens"] || usage["completion_tokens"] || 0

    total_tokens =
      usage["total_tokens"] || usage["total_tokens"] || prompt_tokens + completion_tokens

    Agent.update(
      acc,
      &%{
        &1
        | usage: %{
            prompt_tokens: prompt_tokens,
            completion_tokens: completion_tokens,
            total_tokens: total_tokens
          }
      }
    )
  end

  defp handle_delta(acc, stream_to, delta) do
    case delta["content"] do
      text when is_binary(text) and text != "" ->
        Agent.update(acc, &%{&1 | content: &1.content <> text})
        if stream_to, do: send(stream_to, {:llm_text_delta, text})

      _ ->
        :ok
    end

    case delta["tool_calls"] do
      tool_calls when is_list(tool_calls) ->
        Agent.update(acc, &merge_tool_calls(&1, tool_calls))

      _ ->
        :ok
    end
  end

  defp merge_tool_calls(state, deltas) do
    Enum.reduce(deltas, state, fn delta, state ->
      index = delta["index"] || 0

      existing =
        Map.get(state.tool_calls, index, %{
          "id" => nil,
          "type" => "function",
          "function" => %{"name" => "", "arguments" => ""}
        })

      merged = %{
        "id" => delta["id"] || existing["id"],
        "type" => delta["type"] || existing["type"],
        "function" => %{
          "name" => existing["function"]["name"] <> (get_in(delta, ["function", "name"]) || ""),
          "arguments" =>
            existing["function"]["arguments"] <> (get_in(delta, ["function", "arguments"]) || "")
        }
      }

      put_in(state, [:tool_calls, index], merged)
    end)
  end

  defp build_message(%{content: content, tool_calls: tool_calls}) do
    message = %{
      "role" => "assistant",
      "content" => if(content == "", do: nil, else: content)
    }

    case tool_calls do
      calls when map_size(calls) == 0 ->
        Map.put(message, "tool_calls", nil)

      calls ->
        ordered =
          calls |> Enum.sort_by(fn {index, _} -> index end) |> Enum.map(fn {_, v} -> v end)

        Map.put(message, "tool_calls", ordered)
    end
  end

  defp build_result(state) do
    %{content: content, tool_calls: tool_calls, usage: usage} = state
    message = build_message(%{content: content, tool_calls: tool_calls})
    usage_map = usage || %{prompt_tokens: 0, completion_tokens: 0, total_tokens: 0}
    {message, usage_map}
  end

  defp error_detail(acc) do
    case Agent.get(acc, & &1.raw) do
      "" ->
        "no response body"

      raw ->
        case Jason.decode(raw) do
          {:ok, %{"error" => %{"message" => message}}} -> message
          _ -> String.slice(raw, 0, 300)
        end
    end
  end

  ## Config

  defp config(key) do
    :banter
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(key)
  end

  # Options for Req taken from config; provider options like :api_key or
  # :model are not valid Req options and must be filtered out.
  defp req_options do
    :banter
    |> Application.get_env(__MODULE__, [])
    |> Keyword.take([:plug, :finch, :adapter])
  end
end
