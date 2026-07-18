defmodule BanterWeb.ChatLiveTest do
  use BanterWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Banter.{Conversations, Repo, Tools}
  alias Banter.Conversations.Runner
  alias Banter.LLM.Mock, as: MockLLM
  alias Banter.Tools.MockTool

  setup do
    original_tools = Application.get_env(:banter, :tools)

    on_exit(fn ->
      Application.put_env(:banter, :tools, original_tools)
    end)

    {:ok, conversation} =
      Conversations.create_conversation(%{model: "mock-model", title: "test chat"})

    %{conversation: conversation}
  end

  describe "index" do
    test "renders the empty state and installed tools", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, "#new-chat")
      assert has_element?(view, "#empty-new-chat")
      assert has_element?(view, "#tool-toggle-web_search")
      assert has_element?(view, "#tool-toggle-web_fetch")
      assert has_element?(view, "#model-select")
    end

    test "lists existing conversations in the sidebar", %{
      conn: conn,
      conversation: conversation
    } do
      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, "#conversations-#{conversation.id}", "test chat")
    end

    test "+ new creates a conversation and navigates to it", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#new-chat") |> render_click()

      [newest | _] = Conversations.list_conversations()

      assert_patch(view, "/c/#{newest.id}")
      assert has_element?(view, "#chat-form")
    end
  end

  describe "show" do
    test "renders existing messages", %{conn: conn, conversation: conversation} do
      {:ok, _} =
        Conversations.create_message(conversation, %{role: "user", content: "hello there"})

      {:ok, _} =
        Conversations.create_message(conversation, %{role: "assistant", content: "hi!"})

      {:ok, view, _html} = live(conn, ~p"/c/#{conversation.id}")

      assert has_element?(view, "#messages", "hello there")
      assert has_element?(view, "#messages", "hi!")
    end

    test "renders assistant messages as markdown", %{conn: conn, conversation: conversation} do
      {:ok, _} =
        Conversations.create_message(conversation, %{
          role: "assistant",
          content: "Here is **bold** text and `code`:\n\n```elixir\n:ok\n```"
        })

      {:ok, view, _html} = live(conn, ~p"/c/#{conversation.id}")

      assert has_element?(view, "#messages .markdown strong", "bold")
      assert has_element?(view, "#messages .markdown code", "code")
      assert has_element?(view, "#messages .markdown pre[lang=elixir]")
    end

    test "escapes raw HTML in assistant messages", %{conn: conn, conversation: conversation} do
      {:ok, _} =
        Conversations.create_message(conversation, %{
          role: "assistant",
          content: ~s|<script>alert("xss")</script>|
        })

      {:ok, view, _html} = live(conn, ~p"/c/#{conversation.id}")

      refute has_element?(view, "#messages script")
      assert render(view) =~ "alert"
    end

    test "sending a message streams and renders the reply", %{
      conn: conn,
      conversation: conversation
    } do
      Runner.subscribe(conversation.id)
      MockLLM.set_script([{:text, "a reply from the mock"}])

      {:ok, view, _html} = live(conn, ~p"/c/#{conversation.id}")

      view
      |> element("#chat-form")
      |> render_submit(%{content: "what is the answer?"})

      assert render(view) =~ "what is the answer?"

      assert_receive {:run_finished, _}, 1000
      html = render(view)

      assert html =~ "a reply from the mock"
      refute has_element?(view, "#run-status")

      assert [%{role: "user"}, %{role: "assistant", content: "a reply from the mock"}] =
               Conversations.list_messages(conversation)
    end

    test "the first message retitles a default-titled conversation", %{conn: conn} do
      {:ok, conversation} = Conversations.create_conversation(%{model: "mock-model"})
      Runner.subscribe(conversation.id)
      MockLLM.set_script([{:text, "ok"}])

      {:ok, view, _html} = live(conn, ~p"/c/#{conversation.id}")

      view
      |> element("#chat-form")
      |> render_submit(%{content: "rename me please"})

      assert_receive {:run_finished, _}, 1000

      assert Conversations.get_conversation!(conversation.id).title == "rename me please"
      assert has_element?(view, "#conversations-#{conversation.id}", "rename me please")
    end

    test "shows a live draft while the reply streams", %{
      conn: conn,
      conversation: conversation
    } do
      {:ok, view, _html} = live(conn, ~p"/c/#{conversation.id}")

      send(view.pid, {:run_started, conversation.id})
      send(view.pid, {:llm_delta, "partial reply…"})

      assert has_element?(view, "#assistant-draft", "partial reply…")
    end

    test "renders tool calls and their results", %{conn: conn, conversation: conversation} do
      Application.put_env(:banter, :tools, [Banter.Tools.MockTool])
      MockTool.set_result({:ok, "the tool output"})
      Runner.subscribe(conversation.id)

      MockLLM.set_script([
        {:tool_call, "mock_tool", %{"input" => "some input"}},
        {:text, "final answer"}
      ])

      {:ok, view, _html} = live(conn, ~p"/c/#{conversation.id}")

      view
      |> element("#chat-form")
      |> render_submit(%{content: "use a tool"})

      assert_receive {:run_finished, _}, 1000
      html = render(view)

      assert html =~ "mock_tool"
      assert html =~ "the tool output"
      assert html =~ "final answer"
    end

    test "shows a status line while a tool runs", %{conn: conn, conversation: conversation} do
      {:ok, view, _html} = live(conn, ~p"/c/#{conversation.id}")

      send(view.pid, {:run_started, conversation.id})

      send(
        view.pid,
        {:tool_call_started,
         %{
           "id" => "call_1",
           "function" => %{"name" => "web_search", "arguments" => "{}"}
         }}
      )

      assert has_element?(view, "#run-status", "running web_search…")

      send(view.pid, {:run_finished, conversation.id})
      refute has_element?(view, "#run-status")
    end

    test "surfaces run failures as a flash error", %{conn: conn, conversation: conversation} do
      Runner.subscribe(conversation.id)
      MockLLM.set_script([{:error, "provider exploded"}])

      {:ok, view, _html} = live(conn, ~p"/c/#{conversation.id}")

      view
      |> element("#chat-form")
      |> render_submit(%{content: "boom"})

      assert_receive {:run_failed, _, "provider exploded"}, 1000
      assert render(view) =~ "run failed: provider exploded"
    end

    test "toggling a tool persists the change", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert Tools.enabled?("web_search")

      view
      |> element("#tool-toggle-web_search")
      |> render_click()

      refute Tools.enabled?("web_search")
      assert has_element?(view, ~s(#tool-toggle-web_search[aria-checked="false"]))

      view
      |> element("#tool-toggle-web_search")
      |> render_click()

      assert Tools.enabled?("web_search")
      assert has_element?(view, ~s(#tool-toggle-web_search[aria-checked="true"]))
    end

    test "selecting a model updates the conversation", %{
      conn: conn,
      conversation: conversation
    } do
      {:ok, view, _html} = live(conn, ~p"/c/#{conversation.id}")

      view
      |> element("#model-form")
      |> render_change(%{model: "mock-model-2"})

      assert Conversations.get_conversation!(conversation.id).model == "mock-model-2"
      assert has_element?(view, "#current-model", "mock-model-2")
    end

    test "deleting a conversation navigates back to index", %{
      conn: conn,
      conversation: conversation
    } do
      {:ok, view, _html} = live(conn, ~p"/c/#{conversation.id}")

      view
      |> element("#delete-conversations-#{conversation.id}")
      |> render_click()

      assert_patch(view, "/")

      assert_raise Ecto.NoResultsError, fn ->
        Conversations.get_conversation!(conversation.id)
      end

      refute Repo.aggregate(Banter.Conversations.Message, :count) > 0
    end
  end
end
