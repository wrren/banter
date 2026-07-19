defmodule Banter.Repo.Migrations.CreateCompactionMessages do
  use Ecto.Migration

  def change do
    create table(:compaction_messages) do
      add :conversation_id, references(:conversations, on_delete: :delete_all), null: false
      add :summary_content, :text, null: false
      add :original_message_ids, {:array, :bigint}, null: false
      add :token_count, :integer, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:compaction_messages, [:conversation_id])
  end
end
