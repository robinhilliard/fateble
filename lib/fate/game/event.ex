defmodule Fate.Game.Event do
  use Ash.Resource,
    domain: Fate.Game,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "events"
    repo Fate.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :parent_id, :uuid, allow_nil?: true

    attribute :timestamp, :utc_datetime_usec,
      allow_nil?: false,
      default: &DateTime.utc_now/0

    attribute :type, :atom,
      allow_nil?: false,
      constraints: [
        one_of: [
          :create_campaign,
          :set_system,
          :scene_start,
          :scene_end,
          :zone_create,
          :entity_enter_scene,
          :entity_move,
          :entity_create,
          :entity_modify,
          :entity_remove,
          :aspect_create,
          :aspect_remove,
          :aspect_compel,
          :skill_set,
          :stunt_add,
          :stunt_remove,
          :roll_attack,
          :roll_defend,
          :roll_overcome,
          :roll_create_advantage,
          :invoke,
          :shifts_resolved,
          :redirect_hit,
          :stress_apply,
          :stress_clear,
          :consequence_take,
          :consequence_recover,
          :fate_point_spend,
          :fate_point_earn,
          :fate_point_refresh,
          :concede,
          :taken_out,
          :mook_eliminate
        ]
      ]

    attribute :actor_id, :string, allow_nil?: true
    attribute :target_id, :string, allow_nil?: true
    attribute :exchange_id, :uuid, allow_nil?: true
    attribute :description, :string, allow_nil?: true

    attribute :detail, :map, allow_nil?: true
  end

  relationships do
    belongs_to :parent, __MODULE__ do
      source_attribute :parent_id
      destination_attribute :id
      allow_nil? true
    end
  end

  actions do
    defaults [:read]

    create :append do
      accept [
        :parent_id,
        :type,
        :actor_id,
        :target_id,
        :exchange_id,
        :description,
        :detail
      ]
    end

    update :edit do
      accept [:type, :actor_id, :target_id, :description, :detail]
    end

    destroy :delete
  end
end
