defmodule Banter.Tools.UpdateConversationTitleTest do
  use Banter.DataCase, async: false

  alias Banter.Conversations
  alias Banter.Tools.UpdateConversationTitle

  import Banter.TestFixtures

  setup do
    user = user_fixture()
    conversation = conversation_fixture(user, %{})
    %{user: user, conversation: conversation}
  end

  test "behaviour metadata" do
    assert UpdateConversationTitle.name() == "update_conversation_title"
    assert UpdateConversationTitle.description() =~ "title"

    assert %{"type" => "object", "required" => ["title"]} = UpdateConversationTitle.parameters()
  end

  describe "execute/1" do
    test "returns an ok result for a valid title without touching the database" do
      conversation = conversation_fixture(user_fixture(), %{})

      assert {:ok, result} = UpdateConversationTitle.execute(%{"title" => "Elixir and OTP"})

      assert result == "Conversation title set to: Elixir and OTP"

      # execute/1 performs no write; the conversation is unchanged
      assert Conversations.get_conversation!(conversation.id).title == "new conversation"
    end

    test "trims surrounding whitespace in the confirmation" do
      assert {:ok, result} = UpdateConversationTitle.execute(%{"title" => "  Spaced out  "})
      assert result == "Conversation title set to: Spaced out"
    end

    test "rejects a missing title" do
      assert {:error, "missing required argument: title"} = UpdateConversationTitle.execute(%{})
    end

    test "rejects a non-binary title" do
      assert {:error, "missing required argument: title"} =
               UpdateConversationTitle.execute(%{"title" => 42})
    end

    test "rejects an empty title" do
      assert {:error, "title must not be empty"} =
               UpdateConversationTitle.execute(%{"title" => "   "})
    end

    test "rejects a title longer than 120 characters" do
      assert {:error, error} =
               UpdateConversationTitle.execute(%{"title" => String.duplicate("a", 121)})

      assert error =~ "at most 120"
    end

    test "accepts a title of exactly 120 characters" do
      assert {:ok, _} = UpdateConversationTitle.execute(%{"title" => String.duplicate("a", 120)})
    end
  end

  describe "execute/2 (with conversation context)" do
    test "persists the title on the supplied conversation" do
      conversation = conversation_fixture(user_fixture(), %{})

      assert {:ok, result} =
               UpdateConversationTitle.execute(%{"title" => "Debugging the runner"}, %{
                 conversation: conversation
               })

      assert result == "Conversation title set to: Debugging the runner"
      assert Conversations.get_conversation!(conversation.id).title == "Debugging the runner"
    end

    test "trims the title before persisting" do
      conversation = conversation_fixture(user_fixture(), %{})

      {:ok, _} =
        UpdateConversationTitle.execute(%{"title" => "  Trimmed title  "}, %{
          conversation: conversation
        })

      assert Conversations.get_conversation!(conversation.id).title == "Trimmed title"
    end

    test "rejects an empty title without persisting" do
      conversation = conversation_fixture(user_fixture(), %{})

      assert {:error, "title must not be empty"} =
               UpdateConversationTitle.execute(%{"title" => "   "}, %{conversation: conversation})

      assert Conversations.get_conversation!(conversation.id).title == "new conversation"
    end

    test "rejects an over-length title without persisting" do
      conversation = conversation_fixture(user_fixture(), %{})

      assert {:error, error} =
               UpdateConversationTitle.execute(%{"title" => String.duplicate("b", 121)}, %{
                 conversation: conversation
               })

      assert error =~ "at most 120"
      assert Conversations.get_conversation!(conversation.id).title == "new conversation"
    end

    test "returns the missing-argument error when the title is absent" do
      conversation = conversation_fixture(user_fixture(), %{})

      assert {:error, "missing required argument: title"} =
               UpdateConversationTitle.execute(%{}, %{conversation: conversation})
    end
  end
end
