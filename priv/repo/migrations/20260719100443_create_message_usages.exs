defmodule Banter.Repo.Migrations.CreateMessageUsages do
  use Ecto.Migration

  def change do
    create table(:message_usages) do
      add :message_id, references(:messages, on_delete: :delete_all), null: false
      add :conversation_id, :bigint, null: false
      add :prompt_tokens, :integer, null: false
      add :completion_tokens, :integer, null: false
      add :total_tokens, :integer, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:message_usages, [:message_id])
    create index(:message_usages, [:conversation_id])
  end
end
