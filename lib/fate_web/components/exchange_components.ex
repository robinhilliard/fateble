defmodule FateWeb.ExchangeComponents do
  use FateWeb, :html

  import FateWeb.ActionComponents, only: [entity_name: 2]

  @event_type_labels FateWeb.ActionComponents.event_type_labels()
  @roll_types ~w(roll_attack roll_defend roll_overcome roll_create_advantage)a

  # --- Exchange builder ---

  def exchange_builder(assigns) do
    assigns = assign_new(assigns, :is_observer, fn -> false end)
    interactive = !assigns.is_observer

    assigns = assign(assigns, :interactive, interactive)

    ~H"""
    <div id="exchange-builder" phx-hook={if(@interactive, do: "StepReorder")}>
      <div class="flex items-center justify-between mb-4">
        <h3 class="text-lg font-bold" style="font-family: 'Patrick Hand', cursive;">
          Building: {exchange_label(@building)}
        </h3>
        <%= if @interactive do %>
          <button phx-click="cancel_build" class="text-sm text-red-400 hover:text-red-300">
            Cancel
          </button>
        <% end %>
      </div>

      <%!-- Available step tiles --%>
      <%= if @interactive do %>
        <div class="mb-4">
          <div class="text-xs uppercase text-amber-200/40 mb-2 font-bold">Add Step</div>
          <div class="flex flex-wrap gap-2">
            <%= for step_type <- available_steps(@building) do %>
              <button
                phx-click="add_step"
                phx-value-step_type={step_type}
                draggable="true"
                data-step-type={step_type}
                class="px-3 py-2 bg-amber-900/40 border border-amber-700/30 rounded-lg
                  hover:bg-amber-800/40 hover:border-amber-600/40 transition text-sm cursor-grab"
                style="font-family: 'Patrick Hand', cursive;"
              >
                {step_type_label(step_type)}
              </button>
            <% end %>
          </div>
        </div>
      <% end %>

      <%!-- Build lane --%>
      <div class="mb-4">
        <div class="text-xs uppercase text-amber-200/40 mb-2 font-bold">Build Lane</div>
        <div
          id="build-lane"
          class={[
            "min-h-[3rem] rounded-lg",
            @build_steps == [] && "border border-dashed border-amber-700/20"
          ]}
        >
          <%= if @build_steps == [] do %>
            <div class="text-amber-200/20 text-sm py-4 text-center">
              <%= if @interactive do %>
                Click or drag a step above to begin
              <% else %>
                Waiting for steps...
              <% end %>
            </div>
          <% else %>
            <div class="space-y-2">
              <%= for {step, index} <- Enum.with_index(@build_steps) do %>
                <%= if @editing_step == index do %>
                  <.step_form step={step} index={index} state={@state} />
                <% else %>
                  <.step_summary step={step} index={index} state={@state} is_observer={@is_observer} />
                <% end %>
              <% end %>
            </div>
          <% end %>
        </div>
      </div>

      <%!-- Commit button --%>
      <%= if @interactive && @build_steps != [] && @editing_step == nil do %>
        <button
          phx-click="commit_exchange"
          class="w-full py-3 bg-green-800/60 border border-green-600/30 rounded-lg
            hover:bg-green-700/60 transition text-green-200 font-bold"
        >
          Commit {length(@build_steps)} steps to log
        </button>
      <% end %>
    </div>
    """
  end

  def step_summary(assigns) do
    desc = build_step_description(assigns.step, assigns.state)
    interactive = !assigns[:is_observer]

    assigns =
      assigns
      |> assign(:desc, desc)
      |> assign(:interactive, interactive)

    ~H"""
    <div
      class={[
        "flex items-center gap-2 px-3 py-2 bg-amber-900/30 rounded-lg border border-amber-700/20 hover:bg-amber-900/40 transition step-row",
        if(@interactive, do: "cursor-grab", else: "cursor-default")
      ]}
      phx-click={if(@interactive, do: "edit_step")}
      phx-value-index={@index}
      draggable={if(@interactive, do: "true", else: "false")}
      data-step-index={@index}
    >
      <span class="text-xs text-amber-300/50 font-bold shrink-0">{@index + 1}.</span>
      <span class="text-sm shrink-0" style="font-family: 'Patrick Hand', cursive;">
        {step_type_label(@step.type)}
      </span>
      <span class="text-xs text-amber-200/40 flex-1 truncate">{@desc}</span>
      <%!-- Dice preview for rolls --%>
      <%= if roll_step?(@step.type) do %>
        <div class="flex gap-0.5">
          <%= for val <- @step.detail["fudge_dice"] || [0,0,0,0] do %>
            <span class={"w-4 h-4 rounded text-center text-xs font-bold leading-4 #{die_class(val)}"}>
              {die_display(val)}
            </span>
          <% end %>
          <span class="text-xs text-amber-200/60 ml-1 font-bold">
            {format_rating(@step.detail["raw_total"] || 0)}
          </span>
        </div>
      <% end %>
      <%= if @interactive do %>
        <button
          phx-click="remove_step"
          phx-value-index={@index}
          class="text-red-400/50 hover:text-red-400 text-xs shrink-0"
        >
          ✕
        </button>
      <% end %>
    </div>
    """
  end

  # --- Step forms ---

  def step_form(%{step: %{type: type}} = assigns) when type in @roll_types do
    entities = if assigns.state, do: Map.values(assigns.state.entities), else: []
    skills = actor_skills(assigns.state, assigns.step.actor_id)
    needs_target = type == :roll_attack
    needs_difficulty = type == :roll_overcome

    assigns =
      assigns
      |> assign(:entities, entities)
      |> assign(:skills, skills)
      |> assign(:needs_target, needs_target)
      |> assign(:needs_difficulty, needs_difficulty)

    ~H"""
    <div
      class="p-3 bg-amber-900/20 rounded-lg border border-amber-600/30 space-y-3"
      data-step-index={@index}
    >
      <div class="flex items-center justify-between">
        <span class="text-sm font-bold" style="font-family: 'Patrick Hand', cursive;">
          {step_type_label(@step.type)}
        </span>
        <div class="flex gap-1">
          <button
            phx-click="close_step_form"
            class="text-xs text-amber-200/50 hover:text-amber-200 px-2 py-1 bg-amber-900/40 rounded"
          >
            Done
          </button>
          <button
            phx-click="remove_step"
            phx-value-index={@index}
            class="text-xs text-red-400/50 hover:text-red-400 px-2 py-1"
          >
            ✕
          </button>
        </div>
      </div>

      <form phx-change="update_step_field" id={"step-form-#{@index}"} class="space-y-3">
        <input type="hidden" name="index" value={@index} />
        <%!-- Actor --%>
        <div>
          <label class="block text-xs text-amber-200/50 mb-1">Actor</label>
          <select
            name="actor_id"
            class="w-full px-2 py-1.5 bg-amber-900/30 border border-amber-700/30 rounded text-amber-100 text-sm"
          >
            <option value="">Select...</option>
            <%= for e <- @entities do %>
              <option value={e.id} selected={e.id == @step.actor_id}>{e.name} ({e.kind})</option>
            <% end %>
          </select>
        </div>

        <%!-- Skill --%>
        <div>
          <label class="block text-xs text-amber-200/50 mb-1">Skill</label>
          <select
            name="skill"
            class="w-full px-2 py-1.5 bg-amber-900/30 border border-amber-700/30 rounded text-amber-100 text-sm"
          >
            <option value="">Select...</option>
            <%= for {skill, rating} <- @skills do %>
              <option value={skill} selected={skill == @step.detail["skill"]}>
                {skill} ({format_rating(rating)})
              </option>
            <% end %>
          </select>
        </div>

        <%!-- Target (attack only) --%>
        <%= if @needs_target do %>
          <div>
            <label class="block text-xs text-amber-200/50 mb-1">Target</label>
            <select
              name="target_id"
              class="w-full px-2 py-1.5 bg-amber-900/30 border border-amber-700/30 rounded text-amber-100 text-sm"
            >
              <option value="">Select...</option>
              <%= for e <- @entities do %>
                <option value={e.id} selected={e.id == @step.target_id}>{e.name}</option>
              <% end %>
            </select>
          </div>
        <% end %>

        <%!-- Difficulty (overcome only) --%>
        <%= if @needs_difficulty do %>
          <div>
            <label class="block text-xs text-amber-200/50 mb-1">Difficulty</label>
            <input
              type="number"
              name="difficulty"
              value={@step.detail["difficulty"]}
              placeholder="0"
              class="w-20 px-2 py-1.5 bg-amber-900/30 border border-amber-700/30 rounded text-amber-100 text-sm"
            />
          </div>
        <% end %>
      </form>

      <%!-- Fudge Dice (outside form — uses phx-click, not phx-change) --%>
      <div>
        <label class="block text-xs text-amber-200/50 mb-1">Dice</label>
        <div class="flex items-center gap-3">
          <div class="flex gap-1.5">
            <%= for {val, die_idx} <- Enum.with_index(@step.detail["fudge_dice"] || [0,0,0,0]) do %>
              <button
                phx-click="toggle_die"
                phx-value-index={@index}
                phx-value-die={die_idx}
                class={"w-8 h-8 rounded-lg border-2 font-bold text-base flex items-center justify-center transition-all cursor-pointer hover:scale-110 #{die_class(val)}"}
              >
                {die_display(val)}
              </button>
            <% end %>
          </div>
          <button
            phx-click="auto_roll_dice"
            phx-value-index={@index}
            class="px-3 py-1.5 bg-amber-700/60 hover:bg-amber-600/60 border border-amber-600/40 rounded-lg text-amber-100 text-sm font-bold transition"
          >
            <.icon name="hero-cube-transparent" class="w-4 h-4 inline -mt-0.5" /> Roll
          </button>
          <div class="text-right">
            <div
              class="text-lg font-bold text-amber-100"
              style="font-family: 'Permanent Marker', cursive;"
            >
              {format_rating(@step.detail["raw_total"] || 0)}
            </div>
            <div class="text-xs text-amber-200/30">
              dice {format_rating(Enum.sum(@step.detail["fudge_dice"] || [0, 0, 0, 0]))} + skill {format_rating(
                @step.detail["skill_rating"] || 0
              )}
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  def step_form(%{step: %{type: :invoke}} = assigns) do
    state = assigns.state

    aspects =
      if state do
        entity_aspects =
          state.entities
          |> Map.values()
          |> Enum.flat_map(fn e ->
            Enum.map(
              e.aspects,
              &%{id: &1.id, label: "#{e.name}: #{&1.description}", free_invokes: &1.free_invokes}
            )
          end)

        scene_aspects =
          state.scenes
          |> Enum.filter(&(&1.status == :active))
          |> Enum.flat_map(fn s ->
            Enum.map(
              s.aspects,
              &%{id: &1.id, label: "Scene: #{&1.description}", free_invokes: &1.free_invokes}
            ) ++
              Enum.flat_map(s.zones, fn z ->
                Enum.map(
                  z.aspects,
                  &%{
                    id: &1.id,
                    label: "#{z.name}: #{&1.description}",
                    free_invokes: &1.free_invokes
                  }
                )
              end)
          end)

        entity_aspects ++ scene_aspects
      else
        []
      end

    assigns = assign(assigns, :aspects, aspects)

    ~H"""
    <div
      class="p-3 bg-amber-900/20 rounded-lg border border-amber-600/30 space-y-3"
      data-step-index={@index}
    >
      <div class="flex items-center justify-between">
        <span class="text-sm font-bold" style="font-family: 'Patrick Hand', cursive;">
          Invoke Aspect
        </span>
        <div class="flex gap-1">
          <button
            phx-click="close_step_form"
            class="text-xs text-amber-200/50 hover:text-amber-200 px-2 py-1 bg-amber-900/40 rounded"
          >
            Done
          </button>
          <button
            phx-click="remove_step"
            phx-value-index={@index}
            class="text-xs text-red-400/50 hover:text-red-400 px-2 py-1"
          >
            ✕
          </button>
        </div>
      </div>
      <form phx-change="update_step_field" id={"step-form-#{@index}"} class="space-y-3">
        <input type="hidden" name="index" value={@index} />
        <div>
          <label class="block text-xs text-amber-200/50 mb-1">Aspect</label>
          <select
            name="description"
            class="w-full px-2 py-1.5 bg-amber-900/30 border border-amber-700/30 rounded text-amber-100 text-sm"
          >
            <option value="">Select...</option>
            <%= for a <- @aspects do %>
              <option value={a.label} selected={a.label == @step.detail["description"]}>
                {a.label} {if a.free_invokes > 0, do: "(#{a.free_invokes} free)", else: ""}
              </option>
            <% end %>
          </select>
        </div>
      </form>
    </div>
    """
  end

  def step_form(%{step: %{type: :shifts_resolved}} = assigns) do
    entities = if assigns.state, do: Map.values(assigns.state.entities), else: []
    assigns = assign(assigns, :entities, entities)

    ~H"""
    <div
      class="p-3 bg-amber-900/20 rounded-lg border border-amber-600/30 space-y-3"
      data-step-index={@index}
    >
      <div class="flex items-center justify-between">
        <span class="text-sm font-bold" style="font-family: 'Patrick Hand', cursive;">
          Resolve Shifts
        </span>
        <div class="flex gap-1">
          <button
            phx-click="close_step_form"
            class="text-xs text-amber-200/50 hover:text-amber-200 px-2 py-1 bg-amber-900/40 rounded"
          >
            Done
          </button>
          <button
            phx-click="remove_step"
            phx-value-index={@index}
            class="text-xs text-red-400/50 hover:text-red-400 px-2 py-1"
          >
            ✕
          </button>
        </div>
      </div>
      <form phx-change="update_step_field" id={"step-form-#{@index}"} class="flex gap-3">
        <input type="hidden" name="index" value={@index} />
        <div>
          <label class="block text-xs text-amber-200/50 mb-1">Shifts</label>
          <input
            type="number"
            name="shifts"
            value={@step.detail["shifts"]}
            placeholder="0"
            class="w-20 px-2 py-1.5 bg-amber-900/30 border border-amber-700/30 rounded text-amber-100 text-sm"
          />
        </div>
        <div class="flex-1">
          <label class="block text-xs text-amber-200/50 mb-1">Target</label>
          <select
            name="target_id"
            class="w-full px-2 py-1.5 bg-amber-900/30 border border-amber-700/30 rounded text-amber-100 text-sm"
          >
            <option value="">None</option>
            <%= for e <- @entities do %>
              <option value={e.id} selected={e.id == @step.target_id}>{e.name}</option>
            <% end %>
          </select>
        </div>
      </form>
    </div>
    """
  end

  def step_form(%{step: %{type: :consequence_take}} = assigns) do
    entities = if assigns.state, do: Map.values(assigns.state.entities), else: []
    assigns = assign(assigns, :entities, entities)

    ~H"""
    <div
      class="p-3 bg-amber-900/20 rounded-lg border border-amber-600/30 space-y-3"
      data-step-index={@index}
    >
      <div class="flex items-center justify-between">
        <span class="text-sm font-bold" style="font-family: 'Patrick Hand', cursive;">
          Take Consequence
        </span>
        <div class="flex gap-1">
          <button
            phx-click="close_step_form"
            class="text-xs text-amber-200/50 hover:text-amber-200 px-2 py-1 bg-amber-900/40 rounded"
          >
            Done
          </button>
          <button
            phx-click="remove_step"
            phx-value-index={@index}
            class="text-xs text-red-400/50 hover:text-red-400 px-2 py-1"
          >
            ✕
          </button>
        </div>
      </div>
      <form phx-change="update_step_field" id={"step-form-#{@index}"} class="space-y-3">
        <input type="hidden" name="index" value={@index} />
        <div>
          <label class="block text-xs text-amber-200/50 mb-1">Entity</label>
          <select
            name="target_id"
            class="w-full px-2 py-1.5 bg-amber-900/30 border border-amber-700/30 rounded text-amber-100 text-sm"
          >
            <option value="">Select...</option>
            <%= for e <- @entities do %>
              <option value={e.id} selected={e.id == @step.target_id}>{e.name}</option>
            <% end %>
          </select>
        </div>
        <div class="flex gap-3">
          <div>
            <label class="block text-xs text-amber-200/50 mb-1">Severity</label>
            <select
              name="severity"
              class="px-2 py-1.5 bg-amber-900/30 border border-amber-700/30 rounded text-amber-100 text-sm"
            >
              <option value="mild" selected={@step.detail["severity"] == "mild"}>Mild (2)</option>
              <option value="moderate" selected={@step.detail["severity"] == "moderate"}>
                Moderate (4)
              </option>
              <option value="severe" selected={@step.detail["severity"] == "severe"}>
                Severe (6)
              </option>
              <option value="extreme" selected={@step.detail["severity"] == "extreme"}>
                Extreme (8)
              </option>
            </select>
          </div>
          <div class="flex-1">
            <label class="block text-xs text-amber-200/50 mb-1">Aspect Text</label>
            <input
              type="text"
              name="aspect_text"
              value={@step.detail["aspect_text"]}
              placeholder="Broken Arm"
              class="w-full px-2 py-1.5 bg-amber-900/30 border border-amber-700/30 rounded text-amber-100 text-sm placeholder-amber-200/20"
            />
          </div>
        </div>
      </form>
    </div>
    """
  end

  def step_form(%{step: %{type: :stress_apply}} = assigns) do
    entities = if assigns.state, do: Map.values(assigns.state.entities), else: []

    target =
      assigns.step.target_id && assigns.state &&
        Map.get(assigns.state.entities, assigns.step.target_id)

    tracks = if target, do: target.stress_tracks, else: []

    assigns =
      assigns
      |> assign(:entities, entities)
      |> assign(:tracks, tracks)

    ~H"""
    <div
      class="p-3 bg-amber-900/20 rounded-lg border border-amber-600/30 space-y-3"
      data-step-index={@index}
    >
      <div class="flex items-center justify-between">
        <span class="text-sm font-bold" style="font-family: 'Patrick Hand', cursive;">
          Apply Stress
        </span>
        <div class="flex gap-1">
          <button
            phx-click="close_step_form"
            class="text-xs text-amber-200/50 hover:text-amber-200 px-2 py-1 bg-amber-900/40 rounded"
          >
            Done
          </button>
          <button
            phx-click="remove_step"
            phx-value-index={@index}
            class="text-xs text-red-400/50 hover:text-red-400 px-2 py-1"
          >
            ✕
          </button>
        </div>
      </div>
      <form phx-change="update_step_field" id={"step-form-#{@index}"} class="space-y-3">
        <input type="hidden" name="index" value={@index} />
        <div>
          <label class="block text-xs text-amber-200/50 mb-1">Entity</label>
          <select
            name="target_id"
            class="w-full px-2 py-1.5 bg-amber-900/30 border border-amber-700/30 rounded text-amber-100 text-sm"
          >
            <option value="">Select...</option>
            <%= for e <- @entities do %>
              <option value={e.id} selected={e.id == @step.target_id}>{e.name}</option>
            <% end %>
          </select>
        </div>
        <%= if @tracks != [] do %>
          <div class="flex gap-3">
            <div>
              <label class="block text-xs text-amber-200/50 mb-1">Track</label>
              <select
                name="track_label"
                class="px-2 py-1.5 bg-amber-900/30 border border-amber-700/30 rounded text-amber-100 text-sm"
              >
                <%= for t <- @tracks do %>
                  <option value={t.label} selected={t.label == @step.detail["track_label"]}>
                    {t.label}
                  </option>
                <% end %>
              </select>
            </div>
            <div>
              <label class="block text-xs text-amber-200/50 mb-1">Box</label>
              <input
                type="number"
                name="box_index"
                value={@step.detail["box_index"]}
                placeholder="1"
                min="1"
                class="w-16 px-2 py-1.5 bg-amber-900/30 border border-amber-700/30 rounded text-amber-100 text-sm"
              />
            </div>
          </div>
        <% end %>
      </form>
    </div>
    """
  end

  def step_form(assigns) do
    ~H"""
    <div
      class="flex items-center gap-2 px-3 py-2 bg-amber-900/30 rounded-lg border border-amber-600/30"
      data-step-index={@index}
    >
      <span class="text-xs text-amber-300/50 font-bold">{@index + 1}.</span>
      <span class="text-sm flex-1" style="font-family: 'Patrick Hand', cursive;">
        {step_type_label(@step.type)}
      </span>
      <button
        phx-click="close_step_form"
        class="text-xs text-amber-200/50 hover:text-amber-200 px-2 py-1 bg-amber-900/40 rounded"
      >
        Done
      </button>
      <button
        phx-click="remove_step"
        phx-value-index={@index}
        class="text-xs text-red-400/50 hover:text-red-400 px-2 py-1"
      >
        ✕
      </button>
    </div>
    """
  end

  # --- Action menu ---

  def action_menu(assigns) do
    ~H"""
    <div>
      <%!-- Exchange starters --%>
      <div class="mb-6">
        <div class="text-xs uppercase text-amber-200/40 mb-2 font-bold">Start Exchange</div>
        <div class="grid grid-cols-2 gap-2">
          <%= for {type, label, desc, bg} <- [
            {"attack", "Attack", "Roll, defend, invoke, resolve, absorb", "bg-red-900/30 border-red-700/30 hover:bg-red-800/30"},
            {"overcome", "Overcome", "Roll vs fixed difficulty", "bg-blue-900/30 border-blue-700/30 hover:bg-blue-800/30"},
            {"create_advantage", "Create Advantage", "Roll to create or discover an aspect", "bg-green-900/30 border-green-700/30 hover:bg-green-800/30"},
            {"defend", "Defend", "Oppose an attack or overcome", "bg-amber-900/30 border-amber-700/30 hover:bg-amber-800/30"}
          ] do %>
            <button
              phx-click="start_exchange"
              phx-value-type={type}
              phx-hook="DropTarget"
              id={"exchange-#{type}"}
              data-action-type={type}
              data-action-category="exchange"
              class={"px-4 py-3 border rounded-lg transition text-left cursor-pointer drop-target #{bg}"}
            >
              <div class="font-bold text-sm" style="font-family: 'Permanent Marker', cursive;">
                {label}
              </div>
              <div class="text-xs text-amber-200/30">{desc}</div>
            </button>
          <% end %>
        </div>
      </div>

      <%!-- Quick actions --%>
      <div class="mb-6">
        <div class="text-xs uppercase text-amber-200/40 mb-2 font-bold">Quick Actions</div>
        <div class="grid grid-cols-4 gap-1.5">
          <%= for {type, label} <- quick_action_types() do %>
            <button
              phx-click="open_modal"
              phx-value-type={type}
              phx-hook="DropTarget"
              id={"quick-#{type}"}
              data-action-type={type}
              data-action-category="quick"
              class="px-2 py-1.5 bg-amber-900/20 border border-amber-700/20 rounded-lg
                hover:bg-amber-800/30 transition text-xs cursor-pointer drop-target text-center"
              style="font-family: 'Patrick Hand', cursive;"
            >
              {label}
            </button>
          <% end %>
        </div>
      </div>

      <%!-- Entities reference --%>
      <%= if @state do %>
        <div>
          <div class="text-xs uppercase text-amber-200/40 mb-2 font-bold">Entities</div>
          <div class="space-y-0.5">
            <%= for {section, entities} <- grouped_entities(@state) do %>
              <div class="text-xs uppercase text-amber-200/25 mt-2 mb-1 tracking-wider">
                {section}
              </div>
              <%= for {entity, depth} <- entities do %>
                <div
                  class="flex items-center gap-2 px-2 py-1 rounded hover:bg-amber-900/20 cursor-grab active:cursor-grabbing"
                  style={"margin-left: #{depth * 16}px;"}
                  draggable="true"
                  phx-hook="DraggableEntity"
                  id={"entity-drag-#{entity.id}"}
                  data-entity-id={entity.id}
                  data-entity-name={entity.name}
                >
                  <div class="w-3 h-3 rounded-full shrink-0" style={"background: #{entity.color};"} />
                  <span class="text-sm" style="font-family: 'Patrick Hand', cursive;">
                    {entity.name}
                  </span>
                  <span class="text-xs text-amber-200/30">{entity.kind}</span>
                  <%= if entity.fate_points do %>
                    <span class="ml-auto text-xs text-amber-200/50">FP: {entity.fate_points}</span>
                  <% end %>
                </div>
              <% end %>
            <% end %>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  # --- Exchange metadata ---

  def exchange_label(:attack), do: "Attack Exchange"
  def exchange_label(:overcome), do: "Overcome"
  def exchange_label(:create_advantage), do: "Create Advantage"
  def exchange_label(:defend), do: "Defend"
  def exchange_label(other), do: to_string(other)

  def available_steps(:attack) do
    [
      :roll_attack,
      :roll_defend,
      :invoke,
      :shifts_resolved,
      :stress_apply,
      :consequence_take,
      :redirect_hit,
      :concede,
      :taken_out
    ]
  end

  def available_steps(:overcome), do: [:roll_overcome, :invoke, :shifts_resolved]

  def available_steps(:create_advantage),
    do: [:roll_create_advantage, :invoke, :shifts_resolved, :aspect_create]

  def available_steps(:defend), do: [:roll_defend, :invoke]
  def available_steps(_), do: []

  def quick_action_types do
    [
      {"aspect_create", "Create Aspect"},
      {"aspect_compel", "Compel"},
      {"entity_move", "Move Entity"},
      {"scene_start", "Start Scene"},
      {"scene_end", "End Scene"},
      {"fate_point_spend", "Spend FP"},
      {"fate_point_earn", "Earn FP"},
      {"fate_point_refresh", "Refresh FP"},
      {"entity_create", "Create Entity"},
      {"entity_edit", "Edit Entity"},
      {"skill_set", "Set Skill"},
      {"stunt_add", "Add Stunt"},
      {"stunt_remove", "Remove Stunt"},
      {"set_system", "Set System"},
      {"scene_modify", "Edit Scene"},
      {"note", "Add Note"}
    ]
  end

  # --- Entity grouping for action menu ---

  def grouped_entities(state) do
    all = Map.values(state.entities) |> Enum.reject(& &1.hidden)
    top_level = Enum.filter(all, &is_nil(&1.parent_id))
    children_by_parent = Enum.group_by(all, & &1.parent_id)

    pcs = top_level |> Enum.filter(&(&1.kind == :pc)) |> Enum.sort_by(& &1.name)
    npcs = top_level |> Enum.filter(&(&1.kind == :npc)) |> Enum.sort_by(& &1.name)
    others = top_level |> Enum.reject(&(&1.kind in [:pc, :npc])) |> Enum.sort_by(& &1.name)

    [
      {"Player Characters", flatten_with_children(pcs, children_by_parent, 0)},
      {"NPCs", flatten_with_children(npcs, children_by_parent, 0)},
      {"Other", flatten_with_children(others, children_by_parent, 0)}
    ]
    |> Enum.reject(fn {_, list} -> list == [] end)
  end

  defp flatten_with_children(entities, children_by_parent, depth) do
    Enum.flat_map(entities, fn entity ->
      kids = Map.get(children_by_parent, entity.id, []) |> Enum.sort_by(& &1.name)
      [{entity, depth} | flatten_with_children(kids, children_by_parent, depth + 1)]
    end)
  end

  # --- Step helpers ---

  def step_type_label(type), do: Map.get(@event_type_labels, type, to_string(type))

  def default_step_detail(type) when type in @roll_types do
    %{
      "skill" => nil,
      "skill_rating" => 0,
      "fudge_dice" => [0, 0, 0, 0],
      "raw_total" => 0,
      "difficulty" => nil
    }
  end

  def default_step_detail(:invoke),
    do: %{"aspect_id" => nil, "description" => nil, "free" => true}

  def default_step_detail(:shifts_resolved), do: %{"shifts" => 0, "outcome" => nil}
  def default_step_detail(:stress_apply), do: %{"track_label" => nil, "box_index" => nil}
  def default_step_detail(:consequence_take), do: %{"severity" => "mild", "aspect_text" => nil}
  def default_step_detail(_), do: %{}

  def maybe_update_field(step, params, param_key, struct_key) do
    case params[param_key] do
      nil -> step
      "" -> Map.put(step, struct_key, nil)
      val -> Map.put(step, struct_key, val)
    end
  end

  def parse_step_value("skill_rating", val), do: parse_int_or(val, 0)
  def parse_step_value("difficulty", val), do: parse_int_or(val, nil)
  def parse_step_value("shifts", val), do: parse_int_or(val, 0)
  def parse_step_value("box_index", val), do: parse_int_or(val, nil)
  def parse_step_value(_, val), do: val

  def parse_int_or(nil, default), do: default
  def parse_int_or("", default), do: default

  def parse_int_or(val, default) when is_binary(val) do
    case Integer.parse(val) do
      {n, _} -> n
      :error -> default
    end
  end

  def parse_int_or(val, _default) when is_integer(val), do: val

  def roll_step?(type), do: type in @roll_types

  def actor_skills(state, actor_id) do
    case state && actor_id && Map.get(state.entities, actor_id) do
      nil -> []
      entity -> entity.skills |> Enum.sort_by(&elem(&1, 1), :desc)
    end
  end

  def format_rating(n) when is_integer(n) and n >= 0, do: "+#{n}"
  def format_rating(n) when is_integer(n), do: "#{n}"
  def format_rating(_), do: "+0"

  def die_display(1), do: "+"
  def die_display(-1), do: "−"
  def die_display(_), do: " "

  def die_class(1), do: "bg-green-700 text-green-100 border-green-600"
  def die_class(-1), do: "bg-red-700 text-red-100 border-red-600"
  def die_class(_), do: "bg-gray-600 text-gray-300 border-gray-500"

  def build_step_description(%{type: type} = step, state) when type in @roll_types do
    actor = entity_name(state, step.actor_id) || "?"
    target = entity_name(state, step.target_id)
    skill = step.detail["skill"] || "?"
    dice_str = (step.detail["fudge_dice"] || []) |> Enum.map(&die_display/1) |> Enum.join("")
    total = step.detail["raw_total"] || 0
    vs = if target, do: " vs #{target}", else: ""
    "#{actor} #{skill} [#{dice_str}] = #{format_rating(total)}#{vs}"
  end

  def build_step_description(%{type: :invoke} = step, state) do
    actor = entity_name(state, step.actor_id) || "?"
    desc = step.detail["description"] || "aspect"
    if step.detail["free"], do: "#{actor}: #{desc} (free)", else: "#{actor}: #{desc} (FP)"
  end

  def build_step_description(%{type: :shifts_resolved} = step, state) do
    target = entity_name(state, step.target_id)
    shifts = step.detail["shifts"] || 0
    "#{shifts} shifts#{if target, do: " on #{target}"}"
  end

  def build_step_description(%{type: :stress_apply} = step, state) do
    target = entity_name(state, step.target_id) || "?"
    "#{target} #{step.detail["track_label"] || "?"} box #{step.detail["box_index"] || "?"}"
  end

  def build_step_description(%{type: :consequence_take} = step, state) do
    target = entity_name(state, step.target_id) || "?"
    "#{target} #{step.detail["severity"] || "mild"}: #{step.detail["aspect_text"] || "?"}"
  end

  def build_step_description(%{type: :redirect_hit} = step, state) do
    "#{entity_name(state, step.actor_id) || "?"} → #{entity_name(state, step.target_id) || "?"}"
  end

  def build_step_description(%{type: :concede} = step, state) do
    "#{entity_name(state, step.actor_id) || "?"} concedes"
  end

  def build_step_description(%{type: :taken_out} = step, state) do
    "#{entity_name(state, step.target_id) || entity_name(state, step.actor_id) || "?"} taken out"
  end

  def build_step_description(%{type: :aspect_create} = step, state) do
    target = entity_name(state, step.target_id)
    desc = step.detail["description"] || "?"
    "#{desc}#{if target, do: " on #{target}"}"
  end

  def build_step_description(step, _state), do: to_string(step.type)
end
