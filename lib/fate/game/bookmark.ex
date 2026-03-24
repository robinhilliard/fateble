defmodule Fate.Game.Bookmark do
  use Ash.Resource,
    domain: Fate.Game,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "bookmarks"
    repo Fate.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string, allow_nil?: false
    attribute :description, :string, allow_nil?: true

    attribute :created_at, :utc_datetime_usec,
      allow_nil?: false,
      default: &DateTime.utc_now/0
  end

  relationships do
    belongs_to :event, Fate.Game.Event do
      allow_nil? false
    end
  end

  actions do
    defaults [:read]

    create :create do
      accept [:name, :description, :event_id]
    end

    update :update do
      accept [:name, :description]
    end

    destroy :delete
  end
end
