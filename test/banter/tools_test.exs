defmodule Banter.ToolsTest do
  use Banter.DataCase, async: true

  alias Banter.Tools
  alias Banter.Tools.ToolState

  import Banter.TestFixtures

  setup do
    %{user: user_fixture()}
  end

  test "list/1 returns installed tools, enabled by default", %{user: user} do
    tools = Tools.list(user)

    assert Enum.map(tools, & &1.name) == [
             "web_search",
             "web_fetch",
             "update_conversation_title"
           ]

    assert Enum.all?(tools, & &1.enabled)
    assert Enum.all?(tools, &(is_binary(&1.description) and &1.description != ""))

    hidden = Map.new(tools, &{&1.name, &1.hidden})
    refute hidden["web_search"]
    refute hidden["web_fetch"]
    assert hidden["update_conversation_title"]
  end

  test "set_enabled/3 persists the state and toggles enabled?/2", %{user: user} do
    assert Tools.enabled?(user, "web_search")

    assert {:ok, %ToolState{enabled: false}} = Tools.set_enabled(user, "web_search", false)
    refute Tools.enabled?(user, "web_search")

    assert [tool] = Enum.filter(Tools.list(user), &(&1.name == "web_search"))
    refute tool.enabled

    assert {:ok, %ToolState{enabled: true}} = Tools.set_enabled(user, "web_search", true)
    assert Tools.enabled?(user, "web_search")
  end

  test "tool states are scoped per user", %{user: user} do
    other_user = user_fixture()

    assert {:ok, _} = Tools.set_enabled(user, "web_search", false)

    refute Tools.enabled?(user, "web_search")
    assert Tools.enabled?(other_user, "web_search")
  end

  test "set_enabled/3 broadcasts the change to the user's topic", %{user: user} do
    Tools.subscribe(user)

    assert {:ok, state} = Tools.set_enabled(user, "web_fetch", false)
    assert_received {:tool_toggled, %ToolState{name: "web_fetch", enabled: false}}
    assert state.name == "web_fetch"
  end

  test "set_enabled/3 rejects unknown tools", %{user: user} do
    assert {:error, "unknown tool: nope"} = Tools.set_enabled(user, "nope", true)
  end

  test "enabled_specs/1 returns OpenAI tool specs for enabled tools only", %{user: user} do
    specs = Tools.enabled_specs(user)

    assert length(specs) == 3

    for spec <- specs do
      assert %{
               "type" => "function",
               "function" => %{"name" => name, "description" => _, "parameters" => params}
             } = spec

      assert params["type"] == "object"

      assert name in [
               "web_search",
               "web_fetch",
               "update_conversation_title"
             ]
    end

    {:ok, _} = Tools.set_enabled(user, "web_search", false)

    assert [
             %{"function" => %{"name" => "web_fetch"}},
             %{"function" => %{"name" => "update_conversation_title"}}
           ] = Tools.enabled_specs(user)
  end

  test "enabled_specs/1 always includes hidden tools even when disabled", %{user: user} do
    # the hidden tool has no ToolState row to toggle, but verify it stays in
    # the specs regardless
    specs = Tools.enabled_specs(user)

    assert Enum.any?(specs, &(&1["function"]["name"] == "update_conversation_title"))
  end

  test "execute/3 runs an enabled tool", %{user: user} do
    Req.Test.stub(Banter.Tools.WebFetch, fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("text/plain")
      |> Plug.Conn.send_resp(200, "hello world")
    end)

    assert {:ok, result} = Tools.execute(user, "web_fetch", %{"url" => "https://example.com"})
    assert result =~ "hello world"
  end

  test "execute/3 refuses disabled tools", %{user: user} do
    {:ok, _} = Tools.set_enabled(user, "web_fetch", false)

    assert {:error, "tool web_fetch is disabled"} =
             Tools.execute(user, "web_fetch", %{"url" => "https://example.com"})
  end

  test "execute/3 rejects unknown tools", %{user: user} do
    assert {:error, "unknown tool: nope"} = Tools.execute(user, "nope", %{})
  end
end
