defmodule AnomaExplorer.Repo.Migrations.AddGithubUrlToProtocols do
  use Ecto.Migration

  def change do
    alter table(:protocols) do
      add :github_url, :string
    end
  end
end
