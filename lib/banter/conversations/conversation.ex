defmodule Banter.Conversations.Conversation do
  @moduledoc """
  A single chat conversation with an LLM.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @default_title "new conversation"

  schema "conversations" do
    field :title, :string, default: @default_title
    field :model, :string

    belongs_to :user, Banter.Accounts.User
    belongs_to :provider, Banter.Providers.Provider
    belongs_to :llm_model, Banter.Providers.Model, source: :model_id
    has_many :messages, Banter.Conversations.Message
    has_many :compaction_messages, Banter.Conversations.CompactionMessage

    timestamps(type: :utc_datetime_usec)
  end

  def default_title, do: @default_title

  @doc false
  def changeset(conversation, attrs) do
    conversation
    |> cast(attrs, [:title, :model, :provider_id, :llm_model_id])
    |> validate_required([:title])
    |> validate_length(:title, max: 120)
  end
end
