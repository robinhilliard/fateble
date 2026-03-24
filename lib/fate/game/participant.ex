defmodule Fate.Game.Participant do
  use Ash.Resource,
    domain: Fate.Game,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "participants"
    repo Fate.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string, allow_nil?: false
    attribute :color, :string, allow_nil?: false, default: "#3b82f6"
  end

  relationships do
    has_many :branch_participants, Fate.Game.BranchParticipant
  end

  actions do
    defaults [:read]

    create :create do
      accept [:name, :color]
    end

    update :update do
      accept [:name, :color]
    end

    destroy :delete
  end
end
