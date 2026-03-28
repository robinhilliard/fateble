defmodule Fate.Game do
  use Ash.Domain

  resources do
    resource Fate.Game.Event do
      define(:get_event, action: :read, get_by: [:id], not_found_error?: false)
      define(:list_events, action: :read)
      define(:append_event, action: :append)
      define(:edit_event, action: :edit)
      define(:delete_event, action: :delete)
    end

    resource Fate.Game.Bookmark do
      define(:get_bookmark, action: :read, get_by: [:id], not_found_error?: false)
      define(:list_bookmarks, action: :read)
      define(:create_bookmark, action: :create)
      define(:advance_head, action: :advance_head)
      define(:update_bookmark, action: :update)
      define(:set_status, action: :set_status)
      define(:delete_bookmark, action: :delete)
    end

    resource Fate.Game.BookmarkParticipant do
      define(:list_bookmark_participants, action: :read)
      define(:create_bookmark_participant, action: :create)
      define(:update_bookmark_participant, action: :update)
      define(:delete_bookmark_participant, action: :delete)
    end

    resource Fate.Game.Participant do
      define(:get_participant, action: :read, get_by: [:id], not_found_error?: false)
      define(:list_participants, action: :read)
      define(:create_participant, action: :create)
      define(:update_participant, action: :update)
      define(:delete_participant, action: :delete)
    end
  end
end
