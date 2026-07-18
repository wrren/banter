defmodule BanterWeb.Markdown do
  @moduledoc """
  Renders assistant-authored markdown to HTML.

  GFM extensions (tables, strikethrough, task lists, autolinks) are
  enabled and raw HTML is escaped rather than passed through, so model
  output cannot inject markup into the page.
  """

  @options [
    extension: [strikethrough: true, table: true, autolink: true, tasklist: true],
    render: [escape: true, github_pre_lang: true],
    syntax_highlight: nil
  ]

  @doc """
  Converts markdown to an HTML string safe for `{:raw, ...}` rendering.
  """
  def to_html(content) when is_binary(content) do
    MDEx.to_html!(content, @options)
  end
end
