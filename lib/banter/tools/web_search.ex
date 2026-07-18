defmodule Banter.Tools.WebSearch do
  @moduledoc """
  A tool that searches the web using the Brave Search API.

  Requires an API key, configured via the `BRAVE_SEARCH_API_KEY`
  environment variable (or directly in config):

      config :banter, Banter.Tools.WebSearch, api_key: "..."
  """
  @behaviour Banter.Tools.Tool

  @base_url "https://api.search.brave.com/res/v1"

  @impl true
  def name, do: "web_search"

  @impl true
  def description do
    "Search the web. Returns a numbered list of results, each with a title, " <>
      "URL and short snippet. Use this to find current information, then use " <>
      "the web_fetch tool to read the most relevant pages."
  end

  @impl true
  def parameters do
    %{
      "type" => "object",
      "properties" => %{
        "query" => %{"type" => "string", "description" => "The search query."},
        "count" => %{
          "type" => "integer",
          "description" => "How many results to return, between 1 and 10. Defaults to 5."
        }
      },
      "required" => ["query"]
    }
  end

  @impl true
  def execute(%{"query" => query} = args) when is_binary(query) do
    case api_key() do
      nil ->
        {:error, "web_search is not configured: missing BRAVE_SEARCH_API_KEY"}

      key ->
        query
        |> String.trim()
        |> search(key, count(args))
    end
  end

  def execute(_args), do: {:error, "missing required argument: query"}

  defp search("", _key, _count), do: {:error, "query must not be empty"}

  defp search(query, key, count) do
    [
      base_url: @base_url,
      url: "/web/search",
      params: [q: query, count: count],
      headers: headers(key),
      # Ask for (and transparently decompress) gzipped responses. Do NOT
      # set `accept-encoding` manually: that bypasses Req's decompression
      # and leaves the body as raw gzip bytes.
      compressed: true
    ]
    |> Keyword.merge(req_options())
    |> Req.new()
    |> Req.get()
    |> case do
      {:ok, %{status: 200, body: body}} -> {:ok, format_results(body)}
      {:ok, %{status: status, body: body}} -> {:error, error_message(status, body)}
      {:error, exception} -> {:error, "search request failed: #{Exception.message(exception)}"}
    end
  end

  defp headers(key) do
    [
      {"accept", "application/json"},
      {"x-subscription-token", key}
    ]
  end

  defp format_results(%{"web" => %{"results" => results}}) when is_list(results) do
    case results do
      [] ->
        "No results found."

      results ->
        results
        |> Enum.with_index(1)
        |> Enum.map_join("\n\n", &format_result/1)
    end
  end

  defp format_results(_other), do: "No results found."

  defp format_result({result, index}) do
    [
      "#{index}. #{strip_tags(result["title"])}",
      "   #{result["url"]}",
      result["description"] && "   #{strip_tags(result["description"])}"
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
  end

  # Brave wraps matched terms in <strong> tags; strip all tags from
  # result text sent to the LLM.
  defp strip_tags(nil), do: nil

  defp strip_tags(text) when is_binary(text) do
    String.replace(text, ~r/<[^>]+>/, "")
  end

  defp error_message(status, body) do
    detail =
      case body do
        %{"message" => message} when is_binary(message) -> message
        %{"error" => %{"message" => message}} when is_binary(message) -> message
        _ -> nil
      end

    ["search failed (HTTP #{status})", detail] |> Enum.reject(&is_nil/1) |> Enum.join(": ")
  end

  defp count(args) do
    args
    |> Map.get("count", 5)
    |> normalize_count()
    |> max(1)
    |> min(10)
  end

  defp normalize_count(n) when is_integer(n), do: n

  defp normalize_count(n) when is_binary(n) do
    case Integer.parse(n) do
      {int, _rest} -> int
      :error -> 5
    end
  end

  defp normalize_count(_other), do: 5

  defp api_key, do: Keyword.get(config_options(), :api_key)

  # Options for Req taken from config; tool-specific options like
  # :api_key are not valid Req options and must be filtered out.
  defp req_options do
    Keyword.take(config_options(), [:plug, :finch, :adapter])
  end

  defp config_options do
    Application.get_env(:banter, __MODULE__, [])
  end
end
