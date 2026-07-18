defmodule Banter.Repo.Migrations.CreateMessages do
  use Ecto.Migration

  def change do
    create table(:messages) do
      add :conversation_id, references(:conversations, on_delete: :delete_all), null: false
      add :role, :string, null: false
      add :content, :text
      add :tool_calls, :map
      add :tool_call_id, :string

      timestamps(type: :utc_datetime_usec)
    end

    create index(:messages, [:conversation_id, :inserted_at, :id])
  end
end
