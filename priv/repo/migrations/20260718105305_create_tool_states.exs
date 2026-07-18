defmodule Banter.Repo.Migrations.CreateToolStates do
  use Ecto.Migration

  def change do
    create table(:tool_states) do
      add :name, :string, null: false
      add :enabled, :boolean, null: false, default: true

      timestamps(type: :utc_datetime)
    end

    create unique_index(:tool_states, [:name])
  end
end
