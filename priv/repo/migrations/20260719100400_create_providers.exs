defmodule Banter.Repo.Migrations.CreateProviders do
  use Ecto.Migration

  def change do
    create table(:providers) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :type, :string, null: false, default: "openai_compatible"
      add :base_url, :string, null: false
      add :encrypted_api_key, :string, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:providers, [:user_id])
    create unique_index(:providers, [:user_id, :name])
  end
end
