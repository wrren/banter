defmodule BanterWeb.MarkdownTest do
  use ExUnit.Case, async: true

  alias BanterWeb.Markdown

  test "renders basic markdown" do
    html = Markdown.to_html("Some **bold** and *italic* and `code`.")

    assert html =~ "<strong>bold</strong>"
    assert html =~ "<em>italic</em>"
    assert html =~ "<code>code</code>"
  end

  test "renders GFM tables" do
    html = Markdown.to_html("| a | b |\n|---|---|\n| 1 | 2 |")

    assert html =~ "<table>"
    assert html =~ "<th>a</th>"
    assert html =~ "<td>2</td>"
  end

  test "renders fenced code blocks with the language" do
    html = Markdown.to_html("```elixir\ndef hello, do: :world\n```")

    assert html =~ ~s(<pre lang="elixir">)
    assert html =~ "def hello, do: :world"
  end

  test "renders lists" do
    html = Markdown.to_html("- one\n- two")

    assert html =~ "<ul>"
    assert html =~ "<li>one</li>"
  end

  test "escapes raw HTML instead of passing it through" do
    html = Markdown.to_html(~s|<script>alert("xss")</script>|)

    refute html =~ "<script>"
    assert html =~ "&lt;script&gt;"
  end
end
