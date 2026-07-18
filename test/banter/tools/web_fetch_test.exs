defmodule Banter.Tools.WebFetchTest do
  use ExUnit.Case, async: false

  alias Banter.Tools.WebFetch

  test "behaviour metadata" do
    assert WebFetch.name() == "web_fetch"
    assert WebFetch.description() =~ "Fetch"
    assert %{"type" => "object", "required" => ["url"]} = WebFetch.parameters()
  end

  describe "execute/1" do
    test "extracts main content and strips boilerplate" do
      stub_html("""
      <!DOCTYPE html>
      <html>
        <head>
          <title>Example Page</title>
          <style>body { color: red; }</style>
        </head>
        <body>
          <nav>Home | About | Contact</nav>
          <header>Site header</header>
          <main>
            <h1>Hello world</h1>
            <p>First   paragraph with <a href="https://x.test">a link</a>.</p>
            <p>Second paragraph.</p>
            <script>alert("nope")</script>
          </main>
          <footer>Copyright 2026</footer>
        </body>
      </html>
      """)

      assert {:ok, result} = WebFetch.execute(%{"url" => "https://example.com/page"})

      assert result =~ "Example Page"
      assert result =~ "<https://example.com/page>"
      assert result =~ "Hello world"
      assert result =~ "First paragraph with a link."
      assert result =~ "Second paragraph."
      refute result =~ "nope"
      refute result =~ "Copyright"
      refute result =~ "About"
      refute result =~ "color: red"
    end

    test "keeps the result valid UTF-8 around non-breaking spaces" do
      # Regression test: without the /u flag, the whitespace regex matches
      # bytes and corrupts the two-byte UTF-8 non-breaking space
      # (0xC2 0xA0) into the invalid sequence 0xC2 0x20.
      stub_html("<html><body><p>originates:\u00A0classic cheesecake</p></body></html>")

      assert {:ok, result} = WebFetch.execute(%{"url" => "https://example.com"})
      assert String.valid?(result)
      assert result =~ "originates: classic cheesecake"
    end

    test "drops invalid UTF-8 bytes from the response body" do
      Req.Test.stub(Banter.Tools.WebFetch, fn conn ->
        body = "<html><body><p>valid " <> <<0xC2, 0x20>> <> "text</p></body></html>"

        conn
        |> Plug.Conn.put_resp_content_type("text/html")
        |> Plug.Conn.send_resp(200, body)
      end)

      assert {:ok, result} = WebFetch.execute(%{"url" => "https://example.com"})
      assert String.valid?(result)
      assert result =~ "valid text"
    end

    test "prefers <main> over surrounding body content" do
      stub_html("""
      <html><head><title>T</title></head>
      <body>
        <p>outside content</p>
        <main><p>inside content</p></main>
      </body></html>
      """)

      assert {:ok, result} = WebFetch.execute(%{"url" => "https://example.com"})
      assert result =~ "inside content"
      refute result =~ "outside content"
    end

    test "truncates long pages" do
      original = Application.get_env(:banter, Banter.Tools.WebFetch)

      on_exit(fn ->
        Application.put_env(:banter, Banter.Tools.WebFetch, original)
      end)

      Application.put_env(:banter, Banter.Tools.WebFetch,
        max_chars: 50,
        plug: {Req.Test, Banter.Tools.WebFetch}
      )

      stub_html("<html><body><p>#{String.duplicate("word ", 100)}</p></body></html>")

      assert {:ok, result} = WebFetch.execute(%{"url" => "https://example.com"})
      assert result =~ "[truncated"
      assert String.length(result) < 200
    end

    test "passes through plain text with a source header" do
      Req.Test.stub(Banter.Tools.WebFetch, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("text/plain")
        |> Plug.Conn.send_resp(200, "plain text body")
      end)

      assert {:ok, result} = WebFetch.execute(%{"url" => "https://example.com/file.txt"})
      assert result =~ "<https://example.com/file.txt>"
      assert result =~ "plain text body"
    end

    test "rejects non-text content" do
      Req.Test.stub(Banter.Tools.WebFetch, fn conn ->
        Req.Test.json(conn, %{"some" => "json"})
      end)

      assert {:error, message} = WebFetch.execute(%{"url" => "https://example.com/api"})
      assert message =~ "unsupported content type"
    end

    test "returns an error on HTTP errors" do
      Req.Test.stub(Banter.Tools.WebFetch, fn conn ->
        Plug.Conn.send_resp(conn, 404, "not found")
      end)

      assert {:error, "fetch failed (HTTP 404)"} =
               WebFetch.execute(%{"url" => "https://example.com/missing"})
    end

    test "validates the URL" do
      assert {:error, message} = WebFetch.execute(%{"url" => "not a url"})
      assert message =~ "invalid URL"

      assert {:error, "missing required argument: url"} = WebFetch.execute(%{})
    end
  end

  defp stub_html(html) do
    Req.Test.stub(Banter.Tools.WebFetch, fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("text/html")
      |> Plug.Conn.send_resp(200, html)
    end)
  end
end
