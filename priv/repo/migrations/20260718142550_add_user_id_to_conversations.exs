defmodule Banter.Repo.Migrations.AddUserIdToConversations do
  use Ecto.Migration

  def change do
    # conversations created before accounts existed are orphaned; drop them
    execute "DELETE FROM conversations", "SELECT 1"

    alter table(:conversations) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
    end

    create index(:conversations, [:user_id])
  end
end
