defmodule Banter.Providers.Model do
  use Ecto.Schema
  import Ecto.Changeset

  schema "models" do
    field :name, :string
    field :context_limit, :integer
    field :cost_per_1k_input, :decimal
    field :cost_per_1k_output, :decimal
    field :supports_tools, :boolean, default: true
    field :compaction_threshold, :decimal

    belongs_to :provider, Banter.Providers.Provider

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(model, attrs) do
    model
    |> cast(attrs, [
      :name,
      :context_limit,
      :cost_per_1k_input,
      :cost_per_1k_output,
      :supports_tools,
      :compaction_threshold,
      :provider_id
    ])
    |> validate_required([:name, :context_limit])
    |> validate_number(:context_limit, greater_than: 0)
    |> validate_number(:cost_per_1k_input, greater_than_or_equal_to: 0)
    |> validate_number(:cost_per_1k_output, greater_than_or_equal_to: 0)
    |> validate_number(:compaction_threshold, greater_than: 0, less_than_or_equal_to: 1)
    |> foreign_key_constraint(:provider_id)
    |> unique_constraint([:provider_id, :name])
  end
end
