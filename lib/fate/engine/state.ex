defmodule Fate.Engine.State do
  @moduledoc """
  Derived game state — computed by replaying events, never persisted.
  """

  defmodule Entity do
    defstruct [
      :id,
      :name,
      :kind,
      :fate_points,
      :refresh,
      :mook_count,
      :zone_id,
      :color,
      :avatar,
      :controller_id,
      :table_x,
      :table_y,
      :parent_id,
      aspects: [],
      skills: %{},
      stunts: [],
      stress_tracks: [],
      consequences: [],
      pending_shifts: nil
    ]
  end

  defmodule Aspect do
    defstruct [
      :id,
      :description,
      :role,
      :created_by_entity_id,
      free_invokes: 0,
      hidden: false
    ]
  end

  defmodule Stunt do
    defstruct [:id, :name, :effect]
  end

  defmodule StressTrack do
    defstruct [:label, boxes: 2, checked: []]
  end

  defmodule Consequence do
    defstruct [:id, :severity, :shifts, :aspect_text, recovering: false]
  end

  defmodule PendingShifts do
    defstruct [:exchange_id, :attacker_id, :total_shifts, :remaining_shifts]
  end

  defmodule SceneState do
    defstruct [:id, :name, :description, status: :active, zones: [], aspects: []]
  end

  defmodule ZoneState do
    defstruct [:id, :name, sort_order: 0, aspects: []]
  end

  defmodule DerivedState do
    defstruct [
      :branch_id,
      :head_event_id,
      :campaign_name,
      :system,
      skill_list: [],
      gm_fate_points: 0,
      entities: %{},
      scenes: [],
      valid: true,
      errors: []
    ]
  end
end
