defmodule Banter.Tools.WebSearchTest do
  use ExUnit.Case, async: false

  alias Banter.Tools.WebSearch

  test "behaviour metadata" do
    assert WebSearch.name() == "web_search"
    assert WebSearch.description() =~ "Search the web"

    assert %{"type" => "object", "required" => ["query"]} = WebSearch.parameters()
  end

  describe "execute/1" do
    test "formats results as a compact numbered list" do
      Req.Test.stub(Banter.Tools.WebSearch, fn conn ->
        conn = Plug.Conn.fetch_query_params(conn)
        assert conn.params["q"] == "elixir language"
        assert conn.params["count"] == "2"

        Req.Test.json(conn, %{
          "web" => %{
            "results" => [
              %{
                "title" => "Elixir",
                "url" => "https://elixir-lang.org",
                "description" => "Official website"
              },
              %{
                "title" => "Elixir - Wikipedia",
                "url" => "https://en.wikipedia.org/wiki/Elixir",
                "description" => "Wikipedia article"
              }
            ]
          }
        })
      end)

      assert {:ok, result} = WebSearch.execute(%{"query" => "elixir language", "count" => 2})

      assert result == """
             1. Elixir
                https://elixir-lang.org
                Official website

             2. Elixir - Wikipedia
                https://en.wikipedia.org/wiki/Elixir
                Wikipedia article\
             """
    end

    test "handles results without descriptions" do
      Req.Test.stub(Banter.Tools.WebSearch, fn conn ->
        Req.Test.json(conn, %{
          "web" => %{"results" => [%{"title" => "A", "url" => "https://a.test"}]}
        })
      end)

      assert {:ok, "1. A\n   https://a.test"} = WebSearch.execute(%{"query" => "a"})
    end

    test "decodes gzipped responses" do
      # Regression test: Brave serves gzip when asked. The tool must pass
      # `compressed: true` (setting `accept-encoding` manually bypasses
      # Req's decompression and leaves the body as raw gzip bytes, so the
      # JSON is never decoded and every search "finds nothing").
      body =
        Jason.encode!(%{
          "web" => %{
            "results" => [
              %{"title" => "Gzipped", "url" => "https://gzip.test", "description" => "zipped up"}
            ]
          }
        })
        |> :zlib.gzip()

      Req.Test.stub(Banter.Tools.WebSearch, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("content-encoding", "gzip")
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(200, body)
      end)

      assert {:ok, result} = WebSearch.execute(%{"query" => "gzip"})
      assert result =~ "1. Gzipped"
      assert result =~ "https://gzip.test"
    end

    test "strips <strong> tags from result text" do
      Req.Test.stub(Banter.Tools.WebSearch, fn conn ->
        Req.Test.json(conn, %{
          "web" => %{
            "results" => [
              %{
                "title" => "The <strong>Elixir</strong> language",
                "url" => "https://elixir-lang.org",
                "description" => "A <strong>dynamic, functional</strong> language."
              }
            ]
          }
        })
      end)

      assert {:ok, result} = WebSearch.execute(%{"query" => "elixir"})
      assert result =~ "1. The Elixir language"
      assert result =~ "A dynamic, functional language."
      refute result =~ "<strong>"
    end

    test "reports when there are no results" do
      Req.Test.stub(Banter.Tools.WebSearch, fn conn ->
        Req.Test.json(conn, %{"web" => %{"results" => []}})
      end)

      assert {:ok, "No results found."} = WebSearch.execute(%{"query" => "obscure"})
    end

    test "clamps the count parameter" do
      Req.Test.stub(Banter.Tools.WebSearch, fn conn ->
        conn = Plug.Conn.fetch_query_params(conn)
        assert conn.params["count"] == "10"
        Req.Test.json(conn, %{"web" => %{"results" => []}})
      end)

      assert {:ok, _} = WebSearch.execute(%{"query" => "q", "count" => 99})
    end

    test "returns an error on HTTP errors" do
      Req.Test.stub(Banter.Tools.WebSearch, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(401, ~s({"message": "Invalid subscription token"}))
      end)

      assert {:error, message} = WebSearch.execute(%{"query" => "q"})
      assert message =~ "HTTP 401"
      assert message =~ "Invalid subscription token"
    end

    test "returns an error when the API key is missing" do
      original = Application.get_env(:banter, Banter.Tools.WebSearch)

      on_exit(fn ->
        Application.put_env(:banter, Banter.Tools.WebSearch, original)
      end)

      Application.put_env(:banter, Banter.Tools.WebSearch,
        plug: {Req.Test, Banter.Tools.WebSearch}
      )

      assert {:error, message} = WebSearch.execute(%{"query" => "q"})
      assert message =~ "BRAVE_SEARCH_API_KEY"
    end

    test "validates arguments" do
      assert {:error, "missing required argument: query"} = WebSearch.execute(%{})
      assert {:error, "query must not be empty"} = WebSearch.execute(%{"query" => "  "})
    end
  end
end
