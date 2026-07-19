defmodule Banter.Repo.Migrations.AddProviderAndModelToConversations do
  use Ecto.Migration

  def change do
    alter table(:conversations) do
      add :provider_id, references(:providers, on_delete: :nilify_all)
      add :model_id, references(:models, on_delete: :nilify_all)
    end

    create index(:conversations, [:provider_id])
    create index(:conversations, [:model_id])
  end
end
