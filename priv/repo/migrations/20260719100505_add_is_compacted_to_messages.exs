defmodule Banter.Repo.Migrations.AddIsCompactedToMessages do
  use Ecto.Migration

  def change do
    alter table(:messages) do
      add :is_compacted, :boolean, default: false, null: false
    end

    create index(:messages, [:conversation_id, :is_compacted])
  end
end
