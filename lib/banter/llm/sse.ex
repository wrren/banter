defmodule Banter.LLM.SSE do
  @moduledoc """
  A minimal, incremental parser for Server-Sent Events streams.

  Feed raw chunks into `feed/2` along with the unconsumed buffer from the
  previous call; it returns the complete `data:` payloads found so far and
  the remaining buffer. Non-data lines (event names, ids, comments) are
  ignored, which matches how OpenAI-compatible APIs stream chat
  completions.
  """

  @doc """
  Feeds `chunk` into `buffer`, returning `{events, rest}` where `events`
  is the list of complete `data:` payloads and `rest` is the unconsumed
  remainder to pass to the next call.
  """
  def feed(buffer, chunk) when is_binary(buffer) and is_binary(chunk) do
    {complete, rest} = split_events(buffer <> chunk)
    {Enum.flat_map(complete, &parse_event/1), rest}
  end

  defp split_events(buffer) do
    parts = Regex.split(~r/\r?\n\r?\n/, buffer)

    case List.pop_at(parts, -1) do
      {nil, _} -> {[], buffer}
      {rest, complete} -> {complete, rest || ""}
    end
  end

  defp parse_event(raw) do
    data_lines =
      raw
      |> String.split("\n")
      |> Enum.flat_map(fn line ->
        case String.trim_trailing(line, "\r") do
          "data:" <> data -> [String.trim_leading(data, " ")]
          _other -> []
        end
      end)

    case data_lines do
      [] -> []
      lines -> [Enum.join(lines, "\n")]
    end
  end
end
