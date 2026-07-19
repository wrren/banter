defmodule Banter.ConversationsTest do
  use Banter.DataCase, async: true

  alias Banter.Conversations
  alias Banter.Conversations.{Conversation, Message}

  import Banter.TestFixtures

  setup do
    %{user: user_fixture()}
  end

  describe "conversations" do
    test "create_conversation/2 creates with default title and model", %{user: user} do
      assert {:ok, conversation} =
               Conversations.create_conversation(user, %{model: "gpt-4o-mini"})

      assert conversation.title == Conversation.default_title()
      assert conversation.model == "gpt-4o-mini"
    end

    test "list_conversations/1 returns the user's conversations, most recently active first", %{
      user: user
    } do
      older = conversation_fixture(user, %{title: "older"})
      newer = conversation_fixture(user, %{title: "newer"})

      # bump the older conversation so it sorts first
      {:ok, _} = Conversations.create_message(older, %{role: "user", content: "ping"})

      assert [%Conversation{id: id} | _] = Conversations.list_conversations(user)
      assert id == older.id
      assert Enum.any?(Conversations.list_conversations(user), &(&1.id == newer.id))
    end

    test "list_conversations/1 does not include other users' conversations", %{user: user} do
      _own = conversation_fixture(user, %{title: "mine"})
      _other = conversation_fixture(user_fixture(), %{title: "theirs"})

      assert [%Conversation{title: "mine"}] = Conversations.list_conversations(user)
    end

    test "get_user_conversation!/2 raises for another user's conversation", %{user: user} do
      other = conversation_fixture(user_fixture())

      assert_raise Ecto.NoResultsError, fn ->
        Conversations.get_user_conversation!(user, other.id)
      end
    end

    test "update_conversation/2 changes title and model", %{user: user} do
      conversation = conversation_fixture(user)

      assert {:ok, updated} =
               Conversations.update_conversation(conversation, %{
                 title: "hello",
                 model: "other-model"
               })

      assert updated.title == "hello"
      assert updated.model == "other-model"
    end

    test "delete_conversation/1 removes the conversation and its messages", %{user: user} do
      conversation = conversation_fixture(user)
      {:ok, _} = Conversations.create_message(conversation, %{role: "user", content: "hi"})

      assert {:ok, _} = Conversations.delete_conversation(conversation)
      assert_raise Ecto.NoResultsError, fn -> Conversations.get_conversation!(conversation.id) end
      assert Repo.aggregate(Message, :count) == 0
    end

    test "deleting a user deletes their conversations", %{user: user} do
      conversation = conversation_fixture(user)
      Repo.delete!(user)

      assert_raise Ecto.NoResultsError, fn -> Conversations.get_conversation!(conversation.id) end
    end

    test "maybe_retitle/2 renames a default-titled conversation", %{user: user} do
      conversation = conversation_fixture(user)

      assert {:ok, updated} =
               Conversations.maybe_retitle(conversation, "  what is\n the capital of France? ")

      assert updated.title == "what is the capital of France?"
    end

    test "maybe_retitle/2 truncates long titles", %{user: user} do
      conversation = conversation_fixture(user)
      {:ok, updated} = Conversations.maybe_retitle(conversation, String.duplicate("a", 100))
      assert String.length(updated.title) == 60
    end

    test "maybe_retitle/2 leaves custom titles alone", %{user: user} do
      conversation = conversation_fixture(user, %{title: "custom"})

      assert {:ok, updated} = Conversations.maybe_retitle(conversation, "something else")
      assert updated.title == "custom"
    end
  end

  describe "messages" do
    test "create_message/2 persists a message", %{user: user} do
      conversation = conversation_fixture(user)

      assert {:ok, %Message{} = message} =
               Conversations.create_message(conversation, %{role: "user", content: "hello"})

      assert message.role == "user"
      assert message.content == "hello"
      assert message.conversation_id == conversation.id
    end

    test "create_message/2 requires content or tool calls", %{user: user} do
      conversation = conversation_fixture(user)

      assert {:error, changeset} = Conversations.create_message(conversation, %{role: "user"})
      assert %{content: [_]} = errors_on(changeset)
    end

    test "create_message/2 allows empty content for assistant tool calls", %{user: user} do
      conversation = conversation_fixture(user)

      tool_calls = [
        %{
          "id" => "call_1",
          "type" => "function",
          "function" => %{"name" => "web_search", "arguments" => ~s({"query":"elixir"})}
        }
      ]

      assert {:ok, message} =
               Conversations.create_message(conversation, %{
                 role: "assistant",
                 tool_calls: tool_calls
               })

      assert message.tool_calls == tool_calls
    end

    test "create_message/2 requires tool_call_id for tool messages", %{user: user} do
      conversation = conversation_fixture(user)

      assert {:error, changeset} =
               Conversations.create_message(conversation, %{role: "tool", content: "result"})

      assert %{tool_call_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "list_messages/1 returns messages in chronological order", %{user: user} do
      conversation = conversation_fixture(user)
      {:ok, first} = Conversations.create_message(conversation, %{role: "user", content: "one"})

      {:ok, second} =
        Conversations.create_message(conversation, %{role: "assistant", content: "two"})

      assert [m1, m2] = Conversations.list_messages(conversation)
      assert m1.id == first.id
      assert m2.id == second.id
    end

    test "messages_for_api/1 converts to the OpenAI request shape", %{user: user} do
      conversation = conversation_fixture(user)

      {:ok, _} = Conversations.create_message(conversation, %{role: "user", content: "hi"})

      tool_calls = [
        %{
          "id" => "call_1",
          "type" => "function",
          "function" => %{"name" => "web_search", "arguments" => ~s({"query":"elixir"})}
        }
      ]

      {:ok, _} =
        Conversations.create_message(conversation, %{role: "assistant", tool_calls: tool_calls})

      {:ok, _} =
        Conversations.create_message(conversation, %{
          role: "tool",
          tool_call_id: "call_1",
          content: "search results"
        })

      assert [
               %{"role" => "user", "content" => "hi"},
               %{"role" => "assistant", "content" => nil, "tool_calls" => ^tool_calls},
               %{
                 "role" => "tool",
                 "content" => "search results",
                 "tool_call_id" => "call_1"
               }
             ] =
               conversation
               |> Conversations.list_messages()
               |> Conversations.messages_for_api()
    end
  end
end
