defmodule Fate.Game.Branch do
  use Ash.Resource,
    domain: Fate.Game,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "branches"
    repo Fate.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string, allow_nil?: false

    attribute :status, :atom,
      allow_nil?: false,
      default: :active,
      constraints: [one_of: [:active, :archived, :pruned]]
  end

  relationships do
    belongs_to :head_event, Fate.Game.Event do
      allow_nil? false
    end

    has_many :branch_participants, Fate.Game.BranchParticipant
  end

  actions do
    defaults [:read]

    create :create do
      accept [:name, :head_event_id]
    end

    update :advance_head do
      accept [:head_event_id]
    end

    update :set_status do
      accept [:status]
    end
  end
end
