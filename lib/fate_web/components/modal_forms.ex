defmodule FateWeb.ModalForms do
  @moduledoc """
  Shared field markup for table modals and player-panel action modals.

  Keeps one template per semantic form; callers pass values and optional DOM ids.
  """

  use FateWeb, :html

  alias Phoenix.LiveView.JS

  @doc """
  Entity edit: name, kind, controller, fate points, refresh.

  Pass `input_ids` with optional keys `:name`, `:kind`, `:controller`, `:fate_points`, `:refresh`
  for stable test hooks (table). Omit or pass `%{}` for panel.
  """
  attr :e_name, :string, default: ""
  attr :e_kind, :string, default: ""
  attr :e_controller, :any, default: nil
  attr :e_fp, :string, default: ""
  attr :e_refresh, :string, default: ""
  attr :controller_options, :list, default: []
  attr :input_ids, :map, default: %{}

  def entity_edit_fields(assigns) do
    ids = assigns.input_ids || %{}

    assigns =
      assigns
      |> assign(:_id_name, Map.get(ids, :name))
      |> assign(:_id_kind, Map.get(ids, :kind))
      |> assign(:_id_controller, Map.get(ids, :controller))
      |> assign(:_id_fp, Map.get(ids, :fate_points))
      |> assign(:_id_refresh, Map.get(ids, :refresh))

    ~H"""
    <div>
      <label class="block text-sm text-amber-200/70 mb-1" for={@_id_name || nil}>Name</label>
      <input
        type="text"
        name="name"
        id={@_id_name || nil}
        value={@e_name}
        class="w-full px-3 py-2 bg-amber-900/30 border border-amber-700/30 rounded-lg text-amber-100 text-sm placeholder-amber-200/20"
      />
    </div>
    <div>
      <label class="block text-sm text-amber-200/70 mb-1" for={@_id_kind || nil}>Kind</label>
      <select
        name="kind"
        id={@_id_kind || nil}
        class="w-full px-3 py-2 bg-amber-900/30 border border-amber-700/30 rounded-lg text-amber-100 text-sm"
      >
        <option value="" selected={@e_kind == ""}>— no change —</option>
        <option value="pc" selected={@e_kind == "pc"}>PC</option>
        <option value="npc" selected={@e_kind == "npc"}>NPC</option>
        <option value="mook_group" selected={@e_kind == "mook_group"}>Mook Group</option>
        <option value="organization" selected={@e_kind == "organization"}>Organization</option>
        <option value="vehicle" selected={@e_kind == "vehicle"}>Vehicle</option>
        <option value="item" selected={@e_kind == "item"}>Item</option>
        <option value="hazard" selected={@e_kind == "hazard"}>Hazard</option>
        <option value="custom" selected={@e_kind == "custom"}>Custom</option>
      </select>
    </div>
    <div>
      <label class="block text-sm text-amber-200/70 mb-1" for={@_id_controller || nil}>
        Controller
      </label>
      <select
        name="controller_id"
        id={@_id_controller || nil}
        class="w-full px-3 py-2 bg-amber-900/30 border border-amber-700/30 rounded-lg text-amber-100 text-sm"
      >
        <option value="" selected={is_nil(@e_controller)}>None (GM-controlled)</option>
        <%= for {id, label} <- @controller_options do %>
          <option value={id} selected={id == @e_controller}>{label}</option>
        <% end %>
      </select>
    </div>
    <div>
      <label class="block text-sm text-amber-200/70 mb-1" for={@_id_fp || nil}>Fate Points</label>
      <input
        type="text"
        name="fate_points"
        id={@_id_fp || nil}
        value={@e_fp}
        class="w-full px-3 py-2 bg-amber-900/30 border border-amber-700/30 rounded-lg text-amber-100 text-sm placeholder-amber-200/20"
      />
    </div>
    <div>
      <label class="block text-sm text-amber-200/70 mb-1" for={@_id_refresh || nil}>Refresh</label>
      <input
        type="text"
        name="refresh"
        id={@_id_refresh || nil}
        value={@e_refresh}
        class="w-full px-3 py-2 bg-amber-900/30 border border-amber-700/30 rounded-lg text-amber-100 text-sm placeholder-amber-200/20"
      />
    </div>
    """
  end

  @doc "Start scene: name, description, GM notes; optional hidden scene_id when editing from log."
  attr :scene_id, :string, default: nil
  attr :name_value, :string, default: ""
  attr :scene_description_value, :string, default: ""
  attr :gm_notes_value, :string, default: ""
  attr :name_required, :boolean, default: false

  def scene_start_fields(assigns) do
    ~H"""
    <input :if={@scene_id} type="hidden" name="scene_id" value={@scene_id} />
    <div>
      <label class="block text-sm text-amber-200/70 mb-1">Scene Name</label>
      <input
        type="text"
        name="name"
        placeholder="Dockside Warehouse"
        required={@name_required}
        value={@name_value}
        class="w-full px-3 py-2 bg-amber-900/30 border border-amber-700/30 rounded-lg text-amber-100 text-sm placeholder-amber-200/20"
      />
    </div>
    <div>
      <label class="block text-sm text-amber-200/70 mb-1">Description</label>
      <textarea
        name="scene_description"
        placeholder="A brief framing of the scene"
        rows="3"
        class="w-full px-3 py-2 bg-amber-900/30 border border-amber-700/30 rounded-lg text-amber-100 text-sm placeholder-amber-200/20"
      >{@scene_description_value}</textarea>
    </div>
    <div>
      <label class="block text-sm text-amber-200/70 mb-1">GM Notes</label>
      <textarea
        name="gm_notes"
        placeholder="Private prep notes..."
        rows="3"
        class="w-full px-3 py-2 bg-amber-900/30 border border-amber-700/30 rounded-lg text-amber-100 text-sm placeholder-amber-200/20"
      >{@gm_notes_value}</textarea>
    </div>
    """
  end

  @doc """
  Stunt name + effect. Table uses `stunt_name` / `stunt_effect`; panel uses `name` / `effect`.
  """
  attr :name_field, :string, default: "name"
  attr :effect_field, :string, default: "effect"
  attr :name_value, :string, default: nil
  attr :effect_value, :string, default: nil
  attr :required, :boolean, default: false

  def stunt_add_fields(assigns) do
    ~H"""
    <div>
      <label class="block text-sm text-amber-200/70 mb-1">Stunt Name</label>
      <input
        type="text"
        name={@name_field}
        placeholder="Master Swordswoman"
        required={@required}
        value={@name_value}
        class="w-full px-3 py-2 bg-amber-900/30 border border-amber-700/30 rounded-lg text-amber-100 text-sm placeholder-amber-200/20"
      />
    </div>
    <div>
      <label class="block text-sm text-amber-200/70 mb-1">Effect</label>
      <input
        type="text"
        name={@effect_field}
        placeholder="+2 to Fight when dueling one-on-one"
        required={@required}
        value={@effect_value}
        class="w-full px-3 py-2 bg-amber-900/30 border border-amber-700/30 rounded-lg text-amber-100 text-sm placeholder-amber-200/20"
      />
    </div>
    """
  end

  @doc "Note body + optional target_ref select (panel and table note modals)."
  attr :all_options, :list, default: []
  attr :text, :string, default: ""
  attr :target_ref, :string, default: ""
  attr :note_text_id, :string, default: nil
  attr :autofocus_note, :boolean, default: false

  def note_form_fields(assigns) do
    ~H"""
    <div>
      <label class="block text-sm text-amber-200/70 mb-1">Note</label>
      <textarea
        name="text"
        id={@note_text_id || nil}
        rows="4"
        required
        phx-mounted={if @autofocus_note, do: JS.focus()}
        placeholder="What happened..."
        class="w-full px-3 py-2 bg-amber-900/30 border border-amber-700/30 rounded-lg text-amber-100 text-sm placeholder-amber-200/20"
      >{@text}</textarea>
    </div>
    <div>
      <label class="block text-sm text-amber-200/70 mb-1">About (optional)</label>
      <select
        name="target_ref"
        class="w-full px-3 py-2 bg-amber-900/30 border border-amber-700/30 rounded-lg text-amber-100 text-sm"
      >
        <option value="">General note</option>
        <%= for {value, label} <- @all_options do %>
          <option value={value} selected={value == @target_ref}>{label}</option>
        <% end %>
      </select>
    </div>
    """
  end

  @aspect_role_options [
    {"situation", "Situation"},
    {"boost", "Boost"},
    {"consequence", "Consequence"},
    {"additional", "Additional"},
    {"high_concept", "High Concept"},
    {"trouble", "Trouble"}
  ]

  @doc """
  Aspect on scene/zone/entity: optional target_ref select, description, role (select or fixed hidden), optional hidden checkbox.
  """
  attr :target_options, :list, default: []
  attr :show_target_select, :boolean, default: true
  attr :selected_target_ref, :string, default: ""
  attr :target_select_size, :integer, default: nil
  attr :on_label, :string, default: "On"
  attr :description_value, :string, default: ""
  attr :description_label, :string, default: "Aspect"
  attr :description_placeholder, :string, default: ""
  attr :description_required, :boolean, default: false
  attr :description_autofocus, :boolean, default: false
  attr :role_mode, :atom, default: :select
  attr :fixed_role, :string, default: "situation"
  attr :role_label, :string, default: "Role"
  attr :role_selected, :string, default: "situation"
  attr :show_hidden_checkbox, :boolean, default: false
  attr :hidden_checked, :boolean, default: false

  def aspect_form_fields(assigns) do
    target_attrs =
      if is_integer(assigns.target_select_size) do
        [size: assigns.target_select_size]
      else
        []
      end

    assigns =
      assigns
      |> assign(:target_attrs, target_attrs)
      |> assign(:role_options, @aspect_role_options)

    ~H"""
    <div :if={@show_target_select}>
      <label class="block text-sm text-amber-200/70 mb-1">{@on_label}</label>
      <select
        name="target_ref"
        class="w-full px-3 py-2 bg-amber-900/30 border border-amber-700/30 rounded-lg text-amber-100 text-sm"
        {@target_attrs}
      >
        <%= for {value, label} <- @target_options do %>
          <option value={value} selected={value == @selected_target_ref}>{label}</option>
        <% end %>
      </select>
    </div>
    <div>
      <label class="block text-sm text-amber-200/70 mb-1">{@description_label}</label>
      <input
        type="text"
        name="description"
        placeholder={@description_placeholder}
        required={@description_required}
        value={@description_value}
        class="w-full px-3 py-2 bg-amber-900/30 border border-amber-700/30 rounded-lg text-amber-100 text-sm placeholder-amber-200/20"
        {if @description_autofocus, do: [autofocus: true], else: []}
      />
    </div>
    <%= if @role_mode == :hidden do %>
      <input type="hidden" name="role" value={@fixed_role} />
    <% else %>
      <div>
        <label class="block text-sm text-amber-200/70 mb-1">{@role_label}</label>
        <select
          name="role"
          class="w-full px-3 py-2 bg-amber-900/30 border border-amber-700/30 rounded-lg text-amber-100 text-sm"
        >
          <%= for {value, label} <- @role_options do %>
            <option value={value} selected={value == @role_selected}>{label}</option>
          <% end %>
        </select>
      </div>
    <% end %>
    <label :if={@show_hidden_checkbox} class="flex items-center gap-2 text-sm text-amber-200/70">
      <input
        type="checkbox"
        name="hidden"
        value="true"
        checked={@hidden_checked}
        class="rounded"
      /> Hidden from players
    </label>
    """
  end
end
