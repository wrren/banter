defmodule Banter.Repo.Migrations.CreateConversations do
  use Ecto.Migration

  def change do
    create table(:conversations) do
      add :title, :string, null: false
      add :model, :string, null: false

      timestamps(type: :utc_datetime_usec)
    end
  end
end
