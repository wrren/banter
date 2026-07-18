defmodule Banter.Tools.WebFetch do
  @moduledoc """
  A tool that fetches a URL and returns its essential content.

  For HTML pages, boilerplate (scripts, styles, navigation, headers,
  footers, ads, forms) is removed and the main content is extracted as
  compact plain text, then truncated to a character budget, so the result
  stays small enough to send to the LLM without wasting tokens.

  Options (config, e.g. `config :banter, Banter.Tools.WebFetch, max_chars: 8_000`):

    * `:max_chars` - maximum number of content characters returned
      (default 10_000)
  """
  @behaviour Banter.Tools.Tool

  @default_max_chars 10_000

  @noise_tags ~w(script style noscript nav header footer aside form iframe
                svg template select button object embed link meta)

  @block_tags ~w(address article aside blockquote br dd div dl dt fieldset
                 figcaption figure footer h1 h2 h3 h4 h5 h6 header hr li main
                 nav ol p pre section table td th tr ul)

  @user_agent "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36"

  @impl true
  def name, do: "web_fetch"

  @impl true
  def description do
    "Fetch a web page or text document by URL and return its essential " <>
      "content as plain text. Boilerplate such as navigation, scripts and " <>
      "ads is removed and long pages are truncated."
  end

  @impl true
  def parameters do
    %{
      "type" => "object",
      "properties" => %{
        "url" => %{
          "type" => "string",
          "description" => "The absolute URL to fetch, including http:// or https://."
        }
      },
      "required" => ["url"]
    }
  end

  @impl true
  def execute(%{"url" => url}) when is_binary(url) do
    if valid_url?(url) do
      fetch(url)
    else
      {:error, "invalid URL: #{inspect(url)} (must be an absolute http(s) URL)"}
    end
  end

  def execute(_args), do: {:error, "missing required argument: url"}

  defp valid_url?(url) do
    case URI.parse(url) do
      %URI{scheme: scheme, host: host} when scheme in ["http", "https"] and is_binary(host) ->
        true

      _ ->
        false
    end
  end

  defp fetch(url) do
    [
      url: url,
      headers: [{"user-agent", @user_agent}],
      receive_timeout: 15_000,
      # Ask for (and transparently decompress) gzipped responses. Do NOT
      # set `accept-encoding` manually: that bypasses Req's decompression
      # and leaves the body as raw gzip bytes.
      compressed: true
    ]
    |> Keyword.merge(req_options())
    |> Req.new()
    |> Req.get()
    |> case do
      {:ok, %{status: 200} = response} -> format_response(url, response)
      {:ok, %{status: status}} -> {:error, "fetch failed (HTTP #{status})"}
      {:error, exception} -> {:error, "fetch failed: #{Exception.message(exception)}"}
    end
  end

  defp format_response(url, response) do
    content_type =
      response.headers
      |> Map.get("content-type", [""])
      |> List.first()
      |> String.downcase()

    cond do
      String.contains?(content_type, "html") and is_binary(response.body) ->
        extract_html(url, ensure_valid_utf8(response.body))

      is_binary(response.body) ->
        {:ok, "<#{url}>\n\n" <> truncate(ensure_valid_utf8(response.body))}

      true ->
        {:error, "unsupported content type: #{content_type}"}
    end
  end

  @doc false
  def extract_html(url, html) when is_binary(html) do
    case Floki.parse_document(html) do
      {:ok, document} ->
        title =
          case Floki.find(document, "title") do
            [] -> nil
            [element | _] -> element |> Floki.text() |> clean_text()
          end

        text =
          document
          |> Floki.filter_out(Enum.join(@noise_tags, ","))
          |> main_content()
          |> render_nodes()
          |> clean_text()
          |> truncate()

        case {title, text} do
          {nil, ""} -> {:error, "no readable content found at #{url}"}
          {nil, text} -> {:ok, "<#{url}>\n\n" <> text}
          {title, ""} -> {:ok, "#{title}\n<#{url}>"}
          {title, text} -> {:ok, "#{title}\n<#{url}>\n\n" <> text}
        end

      {:error, _reason} ->
        {:error, "could not parse HTML at #{url}"}
    end
  end

  defp main_content(document) do
    case Floki.find(document, "main") do
      [] ->
        case Floki.find(document, "article") do
          [] -> Floki.find(document, "body")
          nodes -> nodes
        end

      nodes ->
        nodes
    end
  end

  defp render_nodes(nodes) when is_list(nodes) do
    Enum.map_join(nodes, "", &render_node/1)
  end

  defp render_node(text) when is_binary(text), do: text

  defp render_node({"br", _attrs, _children}), do: "\n"

  defp render_node({tag, _attrs, children}) do
    inner = render_nodes(children)

    if tag in @block_tags do
      "\n" <> inner <> "\n"
    else
      inner
    end
  end

  defp render_node(_other), do: ""

  defp clean_text(text) do
    text
    # the `u` flag matters: without it PCRE matches bytes, and `\xA0`
    # would match the second byte of a UTF-8 non-breaking space
    # (0xC2 0xA0), corrupting the string into invalid UTF-8
    |> String.replace(~r/[ \t\xA0]+/u, " ")
    |> String.replace(~r/ *\n+ */u, "\n")
    |> String.replace(~r/\n{3,}/u, "\n\n")
    |> String.trim()
  end

  # Pages with a mislabeled charset can contain bytes that are not valid
  # UTF-8; drop them rather than crash String functions or fail the
  # database insert downstream.
  defp ensure_valid_utf8(text) do
    if String.valid?(text) do
      text
    else
      text
      |> String.chunk(:valid)
      |> Enum.filter(&String.valid?/1)
      |> Enum.join()
    end
  end

  defp truncate(text) do
    max = Keyword.get(config_options(), :max_chars, @default_max_chars)

    if String.length(text) > max do
      String.slice(text, 0, max) <>
        "\n\n[truncated — #{String.length(text) - max} more characters]"
    else
      text
    end
  end

  # Options for Req taken from config; tool-specific options like
  # :max_chars are not valid Req options and must be filtered out.
  defp req_options do
    Keyword.take(config_options(), [:plug, :finch, :adapter])
  end

  defp config_options do
    Application.get_env(:banter, __MODULE__, [])
  end
end
