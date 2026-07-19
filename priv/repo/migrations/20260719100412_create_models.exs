defmodule Banter.Repo.Migrations.CreateModels do
  use Ecto.Migration

  def change do
    create table(:models) do
      add :provider_id, references(:providers, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :context_limit, :integer, null: false
      add :cost_per_1k_input, :decimal, precision: 10, scale: 6
      add :cost_per_1k_output, :decimal, precision: 10, scale: 6
      add :supports_tools, :boolean, default: true, null: false
      add :compaction_threshold, :decimal, precision: 3, scale: 2, default: 0.8

      timestamps(type: :utc_datetime_usec)
    end

    create index(:models, [:provider_id])
    create unique_index(:models, [:provider_id, :name])
  end
end
