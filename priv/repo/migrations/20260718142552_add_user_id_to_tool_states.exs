defmodule Banter.Repo.Migrations.AddUserIdToToolStates do
  use Ecto.Migration

  def change do
    # tool states created before accounts existed have no owner; drop them
    execute "DELETE FROM tool_states", "SELECT 1"

    alter table(:tool_states) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
    end

    drop unique_index(:tool_states, [:name])
    create unique_index(:tool_states, [:user_id, :name])
  end
end
