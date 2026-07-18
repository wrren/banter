defmodule Banter.Tools.ToolState do
  @moduledoc """
  Persists the enabled/disabled state of a tool.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "tool_states" do
    field :name, :string
    field :enabled, :boolean, default: true

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(tool_state, attrs) do
    tool_state
    |> cast(attrs, [:name, :enabled])
    |> validate_required([:name, :enabled])
    |> unique_constraint(:name)
  end
end
