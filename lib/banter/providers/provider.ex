defmodule Banter.Providers.Provider do
  use Ecto.Schema
  import Ecto.Changeset

  @types ~w(openai_compatible)

  schema "providers" do
    field :name, :string
    field :type, :string
    field :base_url, :string
    field :encrypted_api_key, :string

    belongs_to :user, Banter.Accounts.User
    has_many :models, Banter.Providers.Model
    has_many :conversations, Banter.Conversations.Conversation

    timestamps(type: :utc_datetime_usec)
  end

  def types, do: @types

  @doc false
  def changeset(provider, attrs) do
    provider
    |> cast(attrs, [:name, :type, :base_url, :encrypted_api_key, :user_id])
    |> validate_required([:name, :type, :base_url, :encrypted_api_key])
    |> validate_inclusion(:type, @types)
    |> validate_format(:base_url, ~r/^https?:\/\/.+/)
    |> unique_constraint([:user_id, :name])
  end
end
