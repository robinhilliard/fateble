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
      pending_shifts: nil,
      hidden: false
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
    @moduledoc "Scene template — prep object with zones, aspects, and entity placements."
    defstruct [
      :id,
      :name,
      :description,
      :gm_notes,
      zones: [],
      aspects: [],
      entity_placements: %{}
    ]
  end

  defmodule ActiveScene do
    @moduledoc "Active scene instance — independent copy of a template on the table during play."
    defstruct [
      :id,
      :template_id,
      :name,
      :description,
      :gm_notes,
      zones: [],
      aspects: [],
      entity_placements: %{}
    ]
  end

  defmodule ZoneState do
    defstruct [:id, :name, sort_order: 0, aspects: [], hidden: false]
  end

  defmodule DerivedState do
    @core_skills ~w(Athletics Burglary Contacts Crafts Deceive Drive Empathy Fight Investigate Lore Notice Physique Provoke Rapport Resources Shoot Stealth Will)

    defstruct [
      :bookmark_id,
      :head_event_id,
      :campaign_name,
      system: "core",
      skill_list: @core_skills,
      gm_fate_points: 0,
      entities: %{},
      removed_entities: %{},
      scene_templates: [],
      active_scene: nil
    ]
  end
end
