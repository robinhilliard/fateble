defmodule Fate.Game.BranchParticipant do
  use Ash.Resource,
    domain: Fate.Game,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "branch_participants"
    repo Fate.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :role, :atom,
      allow_nil?: false,
      constraints: [one_of: [:player, :gm]]

    attribute :seat_index, :integer, allow_nil?: false
  end

  relationships do
    belongs_to :branch, Fate.Game.Branch do
      allow_nil? false
    end

    belongs_to :participant, Fate.Game.Participant do
      allow_nil? false
    end
  end

  actions do
    defaults [:read]

    create :create do
      accept [:role, :seat_index, :branch_id, :participant_id]
    end

    update :update do
      accept [:role, :seat_index]
    end

    destroy :delete
  end
end
