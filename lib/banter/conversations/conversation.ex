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

    has_many :messages, Banter.Conversations.Message

    timestamps(type: :utc_datetime_usec)
  end

  def default_title, do: @default_title

  @doc false
  def changeset(conversation, attrs) do
    conversation
    |> cast(attrs, [:title, :model])
    |> validate_required([:title, :model])
    |> validate_length(:title, max: 120)
  end
end
