defmodule Banter.ToolsTest do
  use Banter.DataCase, async: true

  alias Banter.Tools
  alias Banter.Tools.ToolState

  test "list/0 returns installed tools, enabled by default" do
    tools = Tools.list()

    assert Enum.map(tools, & &1.name) == ["web_search", "web_fetch"]
    assert Enum.all?(tools, & &1.enabled)
    assert Enum.all?(tools, &(is_binary(&1.description) and &1.description != ""))
  end

  test "set_enabled/2 persists the state and toggles enabled?/1" do
    assert Tools.enabled?("web_search")

    assert {:ok, %ToolState{enabled: false}} = Tools.set_enabled("web_search", false)
    refute Tools.enabled?("web_search")

    assert [tool] = Enum.filter(Tools.list(), &(&1.name == "web_search"))
    refute tool.enabled

    assert {:ok, %ToolState{enabled: true}} = Tools.set_enabled("web_search", true)
    assert Tools.enabled?("web_search")
  end

  test "set_enabled/2 broadcasts the change" do
    Tools.subscribe()

    assert {:ok, state} = Tools.set_enabled("web_fetch", false)
    assert_received {:tool_toggled, %ToolState{name: "web_fetch", enabled: false}}
    assert state.name == "web_fetch"
  end

  test "set_enabled/2 rejects unknown tools" do
    assert {:error, "unknown tool: nope"} = Tools.set_enabled("nope", true)
  end

  test "enabled_specs/0 returns OpenAI tool specs for enabled tools only" do
    specs = Tools.enabled_specs()

    assert length(specs) == 2

    for spec <- specs do
      assert %{
               "type" => "function",
               "function" => %{"name" => name, "description" => _, "parameters" => params}
             } = spec

      assert params["type"] == "object"
      assert name in ["web_search", "web_fetch"]
    end

    {:ok, _} = Tools.set_enabled("web_search", false)

    assert [%{"function" => %{"name" => "web_fetch"}}] = Tools.enabled_specs()
  end

  test "execute/2 runs an enabled tool" do
    Req.Test.stub(Banter.Tools.WebFetch, fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("text/plain")
      |> Plug.Conn.send_resp(200, "hello world")
    end)

    assert {:ok, result} = Tools.execute("web_fetch", %{"url" => "https://example.com"})
    assert result =~ "hello world"
  end

  test "execute/2 refuses disabled tools" do
    {:ok, _} = Tools.set_enabled("web_fetch", false)

    assert {:error, "tool web_fetch is disabled"} =
             Tools.execute("web_fetch", %{"url" => "https://example.com"})
  end

  test "execute/2 rejects unknown tools" do
    assert {:error, "unknown tool: nope"} = Tools.execute("nope", %{})
  end
end
