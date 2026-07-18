defmodule Banter.Release do
  @moduledoc """
  Helpers for invoking release-only commands via `bin/banter eval`.

      bin/banter eval 'Banter.Release.migrate()'
      bin/banter eval 'Banter.Release.rollback(Banter.Repo, 20)'

  The release boots with the application not yet started, so we have to
  load it manually before talking to the repo.
  """

  @app :banter

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.load(@app)
  end
end
