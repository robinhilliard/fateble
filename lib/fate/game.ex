defmodule Fate.Game do
  use Ash.Domain

  resources do
    resource Fate.Game.Event
    resource Fate.Game.Branch
    resource Fate.Game.Bookmark
    resource Fate.Game.Participant
    resource Fate.Game.BranchParticipant
  end
end
