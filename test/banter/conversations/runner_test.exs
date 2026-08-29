defmodule Banter.Conversations.RunnerTest do
  use Banter.DataCase, async: false

  alias Banter.Conversations
  alias Banter.Conversations.Runner
  alias Banter.LLM.Mock, as: MockLLM
  alias Banter.Tools.MockTool

  import Banter.TestFixtures

  setup do
    original_tools = Application.get_env(:banter, :tools)

    Application.put_env(:banter, :tools, [
      Banter.Tools.MockTool,
      Banter.Tools.UpdateConversationTitle
    ])

    on_exit(fn ->
      Application.put_env(:banter, :tools, original_tools)
    end)

    user = user_fixture()

    {:ok, conversation} =
      Conversations.create_conversation(user, %{model: "mock-model", title: "test chat"})

    {:ok, _} =
      Conversations.create_message(conversation, %{role: "user", content: "hello there"})

    Runner.subscribe(conversation.id)

    %{conversation: conversation, user: user}
  end

  test "a simple text run streams and persists the reply", %{conversation: conversation} do
    MockLLM.set_script([{:text, "Hi! How can I help?"}])

    assert :ok = Runner.run(conversation.id)

    assert_received {:run_started, id} when id == conversation.id
    assert_received {:llm_delta, "Hi! "}
    assert_received {:llm_delta, "How "}
    assert_received {:message_appended, %{role: "assistant", content: "Hi! How can I help?"}}
    assert_received {:run_finished, id} when id == conversation.id

    assert [%{role: "user"}, %{role: "assistant", content: "Hi! How can I help?"}] =
             Conversations.list_messages(conversation)
  end

  test "the provider receives history, model and tool specs", %{conversation: conversation} do
    MockLLM.set_script([{:text, "ok"}])

    assert :ok = Runner.run(conversation.id)

    assert [call] = MockLLM.calls()
    assert call.model == "mock-model"

    # the standing system prompt is prepended ahead of the history
    assert [
             %{"role" => "system", "content" => system_prompt},
             %{"role" => "user", "content" => "hello there"}
           ] = call.messages

    assert system_prompt =~ "update_conversation_title"

    assert [
             %{"function" => %{"name" => "mock_tool"}},
             %{"function" => %{"name" => "update_conversation_title"}}
           ] = call.tools
  end

  test "a tool call round trip persists tool results and continues", %{
    conversation: conversation
  } do
    MockTool.set_result({:ok, "mock search results"})

    MockLLM.set_script([
      {:tool_call, "mock_tool", %{"input" => "elixir"}},
      {:text, "Based on the results: elixir is great."}
    ])

    assert :ok = Runner.run(conversation.id)

    assert_received {:tool_call_started, %{"function" => %{"name" => "mock_tool"}}}
    assert_received {:tool_call_finished, _id, "mock_tool", :ok}
    assert_received {:message_appended, %{role: "tool", content: "mock search results"}}
    assert_received {:run_finished, _}

    messages = Conversations.list_messages(conversation)

    assert [
             %{role: "user"},
             %{role: "assistant", tool_calls: [tool_call]},
             %{role: "tool", content: "mock search results", tool_call_id: id},
             %{role: "assistant", content: "Based on the results: elixir is great."}
           ] = messages

    assert tool_call["id"] == id
    assert tool_call["function"]["name"] == "mock_tool"

    # the tool was executed with the decoded arguments
    assert MockTool.calls() == [%{"input" => "elixir"}]

    # the second LLM call saw the tool result in its history, with the
    # standing system prompt prepended
    assert [_, second_call] = MockLLM.calls()

    assert [
             %{"role" => "system"},
             %{"role" => "user"},
             %{"role" => "assistant", "tool_calls" => [_]},
             %{"role" => "tool", "content" => "mock search results"}
           ] = second_call.messages
  end

  test "tool errors are fed back to the LLM as tool results", %{conversation: conversation} do
    MockTool.set_result({:error, "something broke"})

    MockLLM.set_script([
      {:tool_call, "mock_tool", %{"input" => "x"}},
      {:text, "The tool failed, sorry."}
    ])

    assert :ok = Runner.run(conversation.id)

    assert_received {:tool_call_finished, _id, "mock_tool", :error}

    assert [%{role: "user"}, _, %{role: "tool", content: "Error: something broke"}, _] =
             Conversations.list_messages(conversation)
  end

  test "update_conversation_title sets the conversation title", %{conversation: conversation} do
    MockLLM.set_script([
      {:tool_call, "update_conversation_title", %{"title" => "Fixing the flaky test"}},
      {:text, "Done, I renamed the conversation."}
    ])

    assert :ok = Runner.run(conversation.id)

    assert_received {:tool_call_started,
                     %{"function" => %{"name" => "update_conversation_title"}}}

    assert_received {:tool_call_finished, _id, "update_conversation_title", :ok}

    assert_received {:message_appended,
                     %{role: "tool", content: "Conversation title set to: Fixing the flaky test"}}

    assert_received {:run_finished, _}

    # the title was persisted on the conversation
    assert Conversations.get_conversation!(conversation.id).title == "Fixing the flaky test"

    # the second LLM call saw the tool result in its history
    assert [_, second_call] = MockLLM.calls()

    assert [
             %{"role" => "system"},
             %{"role" => "user"},
             %{"role" => "assistant", "tool_calls" => [_]},
             %{"role" => "tool", "content" => "Conversation title set to: Fixing the flaky test"}
           ] = second_call.messages
  end

  test "an invalid title from the tool is fed back as an error", %{conversation: conversation} do
    MockLLM.set_script([
      {:tool_call, "update_conversation_title", %{"title" => ""}},
      {:text, "Sorry, that title was rejected."}
    ])

    assert :ok = Runner.run(conversation.id)

    assert_received {:tool_call_finished, _id, "update_conversation_title", :error}

    # the title was not changed and the error was fed back to the LLM
    assert Conversations.get_conversation!(conversation.id).title == "test chat"

    assert [%{role: "user"}, _, %{role: "tool", content: content}, _] =
             Conversations.list_messages(conversation)

    assert content =~ "must not be empty"
  end

  test "disabled tools produce an error result", %{
    conversation: conversation,
    user: user
  } do
    MockTool.set_result({:ok, "should not run"})
    {:ok, _} = Banter.Tools.set_enabled(user, "mock_tool", false)

    MockLLM.set_script([
      {:tool_call, "mock_tool", %{"input" => "x"}},
      {:text, "ok"}
    ])

    assert :ok = Runner.run(conversation.id)

    assert [%{role: "user"}, _, %{role: "tool", content: content}, _] =
             Conversations.list_messages(conversation)

    assert content =~ "disabled"
    assert MockTool.calls() == []
  end

  test "provider errors fail the run", %{conversation: conversation} do
    MockLLM.set_script([{:error, "provider exploded"}])

    assert {:error, "provider exploded"} = Runner.run(conversation.id)

    assert_received {:run_failed, id, "provider exploded"} when id == conversation.id

    # only the user message was persisted
    assert [%{role: "user"}] = Conversations.list_messages(conversation)
  end

  test "tool call loops are capped", %{conversation: conversation} do
    MockTool.set_result({:ok, "again"})

    MockLLM.set_script(for _ <- 1..10, do: {:tool_call, "mock_tool", %{"input" => "loop"}})

    assert {:error, "too many tool calls"} = Runner.run(conversation.id)

    assert_received {:run_failed, _, "too many tool calls"}
  end

  test "start/1 runs asynchronously under the task supervisor", %{conversation: conversation} do
    MockLLM.set_script([{:text, "async reply"}])

    assert {:ok, pid} = Runner.start(conversation.id)

    ref = Process.monitor(pid)
    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 1000

    assert_received {:run_finished, id} when id == conversation.id

    assert [%{role: "user"}, %{role: "assistant", content: "async reply"}] =
             Conversations.list_messages(conversation)
  end
end
