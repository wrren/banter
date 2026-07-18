defmodule Banter.Conversations.Message do
  @moduledoc """
  A single message within a conversation.

  Messages follow the OpenAI chat completions shape so they can be sent
  directly to OpenAI-compatible providers:

    * `role` - one of `"user"`, `"assistant"` or `"tool"`
    * `content` - the text body (may be nil for assistant messages that
      only carry tool calls)
    * `tool_calls` - a list of tool call maps as returned by the provider,
      e.g. `%{"id" => "call_1", "type" => "function", "function" => %{"name" => "web_search", "arguments" => "{...}"}}`
    * `tool_call_id` - for `role: "tool"` messages, the id of the tool call
      being answered
  """
  use Ecto.Schema
  import Ecto.Changeset

  @roles ~w(user assistant tool)

  schema "messages" do
    field :role, :string
    field :content, :string
    field :tool_calls, {:array, :map}
    field :tool_call_id, :string

    belongs_to :conversation, Banter.Conversations.Conversation

    timestamps(type: :utc_datetime_usec)
  end

  def roles, do: @roles

  @doc false
  def changeset(message, attrs) do
    message
    |> cast(attrs, [:role, :content, :tool_calls, :tool_call_id])
    |> validate_required([:role])
    |> validate_inclusion(:role, @roles)
    |> validate_content_or_tool_calls()
    |> validate_tool_call_id()
  end

  defp validate_content_or_tool_calls(changeset) do
    content = get_field(changeset, :content)
    tool_calls = get_field(changeset, :tool_calls)

    if (is_nil(content) or content == "") and tool_calls in [nil, []] do
      add_error(changeset, :content, "must be present when there are no tool calls")
    else
      changeset
    end
  end

  defp validate_tool_call_id(changeset) do
    if get_field(changeset, :role) == "tool" do
      validate_required(changeset, [:tool_call_id])
    else
      changeset
    end
  end
end
