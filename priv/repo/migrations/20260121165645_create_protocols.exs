defmodule AnomaExplorer.Repo.Migrations.CreateProtocols do
  use Ecto.Migration

  def change do
    create table(:protocols) do
      add :name, :string, null: false
      add :description, :text
      add :active, :boolean, default: true, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:protocols, [:name])
    create index(:protocols, [:active])
  end
end
