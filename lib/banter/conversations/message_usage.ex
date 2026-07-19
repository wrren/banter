defmodule Banter.Conversations.MessageUsage do
  use Ecto.Schema
  import Ecto.Changeset

  schema "message_usages" do
    field :prompt_tokens, :integer
    field :completion_tokens, :integer
    field :total_tokens, :integer

    belongs_to :message, Banter.Conversations.Message
    field :conversation_id, :integer

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(message_usage, attrs) do
    message_usage
    |> cast(attrs, [
      :message_id,
      :conversation_id,
      :prompt_tokens,
      :completion_tokens,
      :total_tokens
    ])
    |> validate_required([
      :message_id,
      :conversation_id,
      :prompt_tokens,
      :completion_tokens,
      :total_tokens
    ])
    |> validate_number(:prompt_tokens, greater_than_or_equal_to: 0)
    |> validate_number(:completion_tokens, greater_than_or_equal_to: 0)
    |> validate_number(:total_tokens, greater_than_or_equal_to: 0)
  end
end
