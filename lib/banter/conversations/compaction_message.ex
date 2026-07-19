defmodule Banter.Conversations.CompactionMessage do
  use Ecto.Schema
  import Ecto.Changeset

  schema "compaction_messages" do
    field :summary_content, :string
    field :original_message_ids, {:array, :integer}
    field :token_count, :integer

    belongs_to :conversation, Banter.Conversations.Conversation

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(compaction_message, attrs) do
    compaction_message
    |> cast(attrs, [:conversation_id, :summary_content, :original_message_ids, :token_count])
    |> validate_required([
      :conversation_id,
      :summary_content,
      :original_message_ids,
      :token_count
    ])
    |> validate_number(:token_count, greater_than_or_equal_to: 0)
  end
end
