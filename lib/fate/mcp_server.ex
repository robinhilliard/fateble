defmodule Fate.McpServer do
  @moduledoc """
  MCP server for AI-assisted Fate RPG prep.
  Mounted as an HTTP endpoint via ExMCP.HttpPlug on the Phoenix router.
  """

  use ExMCP.Server.Handler

  alias Fate.Engine

  @impl true
  def init(args) do
    branch_id = Keyword.get(args, :branch_id) || args[:branch_id] || find_active_branch()
    {:ok, %{branch_id: branch_id}}
  end

  defp find_active_branch do
    case Ash.read(Fate.Game.Branch, filter: [status: :active], load: [:head_event]) do
      {:ok, branches} when branches != [] ->
        branches
        |> Enum.max_by(fn b -> b.head_event && b.head_event.timestamp end, DateTime, fn -> nil end)
        |> Map.get(:id)

      _ ->
        nil
    end
  end

  @impl true
  def handle_initialize(_params, state) do
    {:ok, %{
      name: "fate-rpg",
      version: "0.1.0",
      capabilities: %{
        tools: %{},
        resources: %{}
      }
    }, state}
  end

  @impl true
  def handle_list_tools(_cursor, state) do
    tools = [
      %{
        name: "get_game",
        description: "Get an overview of the current game state: campaign name, system, entities, scenes",
        input_schema: %{type: "object", properties: %{}}
      },
      %{
        name: "list_entities",
        description: "List all entities with their name, kind, aspects, and fate points",
        input_schema: %{
          type: "object",
          properties: %{
            kind: %{type: "string", description: "Filter by kind: pc, npc, mook_group, organization, vehicle, item, hazard, custom"}
          }
        }
      },
      %{
        name: "get_entity",
        description: "Get full details of a specific entity: aspects, skills, stunts, stress tracks, consequences",
        input_schema: %{
          type: "object",
          properties: %{entity_id: %{type: "string", description: "The entity's ID"}},
          required: ["entity_id"]
        }
      },
      %{
        name: "list_scenes",
        description: "List all scenes with their status, zones, and situation aspects",
        input_schema: %{type: "object", properties: %{}}
      },
      %{
        name: "get_action_log",
        description: "Get recent events from the action log",
        input_schema: %{
          type: "object",
          properties: %{limit: %{type: "integer", description: "Max events to return (default 20)"}}
        }
      },
      %{
        name: "create_entity",
        description: "Create a new entity (character, NPC, organization, vehicle, etc.) with aspects, skills, stunts, and stress tracks",
        input_schema: %{
          type: "object",
          properties: %{
            name: %{type: "string", description: "Entity name"},
            kind: %{type: "string", description: "Entity kind: pc, npc, mook_group, organization, vehicle, item, hazard, custom"},
            color: %{type: "string", description: "Hex color for visual coding (e.g. #dc2626)"},
            fate_points: %{type: "integer", description: "Starting fate points"},
            refresh: %{type: "integer", description: "Refresh rate"},
            mook_count: %{type: "integer", description: "Number of mooks (for mook_group)"},
            aspects: %{type: "array", description: "List of aspects", items: %{type: "object", properties: %{description: %{type: "string"}, role: %{type: "string"}, hidden: %{type: "boolean"}}, required: ["description"]}},
            skills: %{type: "object", description: "Skill ratings e.g. {\"Fight\": 4}", additionalProperties: %{type: "integer"}},
            stunts: %{type: "array", items: %{type: "object", properties: %{name: %{type: "string"}, effect: %{type: "string"}}, required: ["name", "effect"]}},
            stress_tracks: %{type: "array", items: %{type: "object", properties: %{label: %{type: "string"}, boxes: %{type: "integer"}}, required: ["label"]}},
            controller_id: %{type: "string", description: "Participant ID who controls this entity"}
          },
          required: ["name", "kind"]
        }
      },
      %{
        name: "update_entity",
        description: "Modify an entity's base properties (name, kind, color, fate_points, refresh)",
        input_schema: %{
          type: "object",
          properties: %{
            entity_id: %{type: "string"}, name: %{type: "string"}, kind: %{type: "string"},
            color: %{type: "string"}, fate_points: %{type: "integer"}, refresh: %{type: "integer"}
          },
          required: ["entity_id"]
        }
      },
      %{
        name: "add_aspect",
        description: "Add an aspect to an entity, scene, or zone",
        input_schema: %{
          type: "object",
          properties: %{
            target_id: %{type: "string", description: "Entity, scene, or zone ID"},
            target_type: %{type: "string", description: "entity, scene, or zone (default: entity)"},
            description: %{type: "string", description: "The aspect text"},
            role: %{type: "string", description: "high_concept, trouble, additional, situation, boost, consequence"},
            hidden: %{type: "boolean"}, free_invokes: %{type: "integer"}
          },
          required: ["target_id", "description"]
        }
      },
      %{
        name: "set_skill",
        description: "Set or update skill ratings on an entity. Pass multiple skills at once.",
        input_schema: %{
          type: "object",
          properties: %{
            entity_id: %{type: "string"},
            skills: %{type: "object", additionalProperties: %{type: "integer"}}
          },
          required: ["entity_id", "skills"]
        }
      },
      %{
        name: "add_stunt",
        description: "Add a stunt to an entity",
        input_schema: %{
          type: "object",
          properties: %{entity_id: %{type: "string"}, name: %{type: "string"}, effect: %{type: "string"}},
          required: ["entity_id", "name", "effect"]
        }
      },
      %{
        name: "create_bookmark",
        description: "Create a named bookmark on the current head event. Use to mark milestones like 'prep complete' or 'before the fight' for later return or what-if exploration.",
        input_schema: %{
          type: "object",
          properties: %{
            name: %{type: "string", description: "Bookmark name"},
            description: %{type: "string", description: "Optional note about this point in the timeline"}
          },
          required: ["name"]
        }
      },
      %{
        name: "list_bookmarks",
        description: "List all named bookmarks",
        input_schema: %{type: "object", properties: %{}}
      },
      %{
        name: "fork_from_bookmark",
        description: "Create a new branch starting from a bookmarked event. Use for what-if exploration — e.g. try different character builds, then pick one.",
        input_schema: %{
          type: "object",
          properties: %{
            bookmark_name: %{type: "string", description: "Name of the bookmark to fork from"},
            branch_name: %{type: "string", description: "Name for the new branch"}
          },
          required: ["bookmark_name", "branch_name"]
        }
      },
      %{
        name: "switch_branch",
        description: "Switch the MCP server to operate on a different branch",
        input_schema: %{
          type: "object",
          properties: %{
            branch_id: %{type: "string", description: "Branch ID to switch to"},
            branch_name: %{type: "string", description: "Or find by name instead of ID"}
          }
        }
      },
      %{
        name: "list_branches",
        description: "List all branches with their status and head event timestamp",
        input_schema: %{type: "object", properties: %{}}
      },
      %{
        name: "create_scene",
        description: "Create a new scene with zones and situation aspects",
        input_schema: %{
          type: "object",
          properties: %{
            name: %{type: "string"}, description: %{type: "string"},
            zones: %{type: "array", items: %{type: "object", properties: %{name: %{type: "string"}}, required: ["name"]}},
            aspects: %{type: "array", items: %{type: "object", properties: %{description: %{type: "string"}, role: %{type: "string"}}, required: ["description"]}}
          },
          required: ["name"]
        }
      }
    ]

    {:ok, tools, nil, state}
  end

  @impl true
  def handle_call_tool("get_game", _args, state) do
    with {:ok, derived} <- Engine.derive_state(state.branch_id) do
      summary = %{
        campaign_name: derived.campaign_name,
        system: derived.system,
        skill_list: derived.skill_list,
        gm_fate_points: derived.gm_fate_points,
        entity_count: map_size(derived.entities),
        entities: derived.entities |> Map.values() |> Enum.map(&entity_summary/1),
        active_scene: derived.scenes |> Enum.find(&(&1.status == :active)) |> scene_summary()
      }

      {:ok, [%{type: "text", text: Jason.encode!(summary, pretty: true)}], state}
    else
      _ -> {:error, %{code: -32000, message: "Failed to derive state"}, state}
    end
  end

  def handle_call_tool("list_entities", args, state) do
    with {:ok, derived} <- Engine.derive_state(state.branch_id) do
      kind_filter = args["kind"]

      entities =
        derived.entities
        |> Map.values()
        |> then(fn entities ->
          if kind_filter do
            kind_atom = String.to_existing_atom(kind_filter)
            Enum.filter(entities, &(&1.kind == kind_atom))
          else
            entities
          end
        end)
        |> Enum.map(&entity_detail/1)

      {:ok, [%{type: "text", text: Jason.encode!(entities, pretty: true)}], state}
    end
  end

  def handle_call_tool("get_entity", %{"entity_id" => entity_id}, state) do
    with {:ok, derived} <- Engine.derive_state(state.branch_id) do
      case Map.get(derived.entities, entity_id) do
        nil -> {:ok, [%{type: "text", text: "Entity not found: #{entity_id}"}], state}
        entity -> {:ok, [%{type: "text", text: Jason.encode!(entity_detail(entity), pretty: true)}], state}
      end
    end
  end

  def handle_call_tool("list_scenes", _args, state) do
    with {:ok, derived} <- Engine.derive_state(state.branch_id) do
      scenes = Enum.map(derived.scenes, &scene_detail/1)
      {:ok, [%{type: "text", text: Jason.encode!(scenes, pretty: true)}], state}
    end
  end

  def handle_call_tool("get_action_log", args, state) do
    limit = args["limit"] || 20

    with {:ok, branch} <- Ash.get(Fate.Game.Branch, state.branch_id),
         {:ok, events} <- Engine.load_event_chain(branch.head_event_id) do
      recent = events |> Enum.take(-limit) |> Enum.map(&event_summary/1)
      {:ok, [%{type: "text", text: Jason.encode!(recent, pretty: true)}], state}
    else
      _ -> {:error, %{code: -32000, message: "Failed to load action log"}, state}
    end
  end

  def handle_call_tool("create_entity", args, state) do
    entity_id = Ash.UUID.generate()

    detail = %{
      "entity_id" => entity_id,
      "name" => args["name"], "kind" => args["kind"],
      "color" => args["color"] || "#6b7280",
      "fate_points" => args["fate_points"], "refresh" => args["refresh"],
      "mook_count" => args["mook_count"], "controller_id" => args["controller_id"],
      "aspects" => args["aspects"] || [], "skills" => args["skills"] || %{},
      "stunts" => args["stunts"] || [], "stress_tracks" => args["stress_tracks"] || []
    }

    case Engine.append_event(state.branch_id, %{
      type: :entity_create,
      description: "Create #{args["name"]} (#{args["kind"]})",
      detail: detail
    }) do
      {:ok, _state, _event} ->
        {:ok, [%{type: "text", text: "Created '#{args["name"]}' (#{args["kind"]}) with ID #{entity_id}"}], state}

      {:error, reason} ->
        {:error, %{code: -32000, message: "Failed: #{inspect(reason)}"}, state}
    end
  end

  def handle_call_tool("update_entity", args, state) do
    entity_id = args["entity_id"]
    detail = Map.drop(args, ["entity_id"]) |> Map.put("entity_id", entity_id)

    case Engine.append_event(state.branch_id, %{
      type: :entity_modify, target_id: entity_id,
      description: "Modify entity #{entity_id}", detail: detail
    }) do
      {:ok, _, _} -> {:ok, [%{type: "text", text: "Updated entity #{entity_id}"}], state}
      {:error, reason} -> {:error, %{code: -32000, message: inspect(reason)}, state}
    end
  end

  def handle_call_tool("add_aspect", args, state) do
    detail = %{
      "target_id" => args["target_id"], "target_type" => args["target_type"] || "entity",
      "description" => args["description"], "role" => args["role"] || "additional",
      "hidden" => args["hidden"] || false, "free_invokes" => args["free_invokes"] || 0
    }

    case Engine.append_event(state.branch_id, %{
      type: :aspect_create, target_id: args["target_id"],
      description: "Add aspect: #{args["description"]}", detail: detail
    }) do
      {:ok, _, _} -> {:ok, [%{type: "text", text: "Added aspect '#{args["description"]}' to #{args["target_id"]}"}], state}
      {:error, reason} -> {:error, %{code: -32000, message: inspect(reason)}, state}
    end
  end

  def handle_call_tool("set_skill", %{"entity_id" => entity_id, "skills" => skills}, state) do
    results =
      Enum.map(skills, fn {skill, rating} ->
        Engine.append_event(state.branch_id, %{
          type: :skill_set, target_id: entity_id,
          description: "Set #{skill} to #{rating}",
          detail: %{"entity_id" => entity_id, "skill" => skill, "rating" => rating}
        })
      end)

    errors = Enum.filter(results, &match?({:error, _}, &1))

    if errors == [] do
      skill_list = Enum.map_join(skills, ", ", fn {k, v} -> "#{k}: +#{v}" end)
      {:ok, [%{type: "text", text: "Set skills on #{entity_id}: #{skill_list}"}], state}
    else
      {:error, %{code: -32000, message: "Some skills failed"}, state}
    end
  end

  def handle_call_tool("add_stunt", args, state) do
    case Engine.append_event(state.branch_id, %{
      type: :stunt_add, target_id: args["entity_id"],
      description: "Add stunt: #{args["name"]}",
      detail: %{"entity_id" => args["entity_id"], "name" => args["name"], "effect" => args["effect"]}
    }) do
      {:ok, _, _} -> {:ok, [%{type: "text", text: "Added stunt '#{args["name"]}' to #{args["entity_id"]}"}], state}
      {:error, reason} -> {:error, %{code: -32000, message: inspect(reason)}, state}
    end
  end

  def handle_call_tool("create_scene", args, state) do
    detail = %{
      "scene_id" => Ash.UUID.generate(), "name" => args["name"],
      "description" => args["description"], "zones" => args["zones"] || [],
      "aspects" => Enum.map(args["aspects"] || [], fn a -> Map.put_new(a, "role", "situation") end)
    }

    case Engine.append_event(state.branch_id, %{
      type: :scene_start, description: "Start scene: #{args["name"]}", detail: detail
    }) do
      {:ok, _, _} ->
        {:ok, [%{type: "text", text: "Created scene '#{args["name"]}' with #{length(detail["zones"])} zones"}], state}

      {:error, reason} ->
        {:error, %{code: -32000, message: inspect(reason)}, state}
    end
  end

  def handle_call_tool("create_bookmark", args, state) do
    with {:ok, branch} <- Ash.get(Fate.Game.Branch, state.branch_id),
         {:ok, bookmark} <- Ash.create(Fate.Game.Bookmark, %{
           name: args["name"],
           description: args["description"],
           event_id: branch.head_event_id
         }, action: :create) do
      {:ok, [%{type: "text", text: "Bookmarked '#{args["name"]}' at event #{bookmark.event_id}"}], state}
    else
      {:error, reason} -> {:error, %{code: -32000, message: inspect(reason)}, state}
    end
  end

  def handle_call_tool("list_bookmarks", _args, state) do
    case Ash.read(Fate.Game.Bookmark, load: [:event]) do
      {:ok, bookmarks} ->
        list = Enum.map(bookmarks, fn b ->
          %{
            id: b.id,
            name: b.name,
            description: b.description,
            event_id: b.event_id,
            created_at: b.created_at
          }
        end)
        {:ok, [%{type: "text", text: Jason.encode!(list, pretty: true)}], state}

      _ ->
        {:ok, [%{type: "text", text: "[]"}], state}
    end
  end

  def handle_call_tool("fork_from_bookmark", args, state) do
    bookmark_name = args["bookmark_name"]
    branch_name = args["branch_name"]

    with {:ok, bookmarks} <- Ash.read(Fate.Game.Bookmark, filter: [name: bookmark_name]),
         %Fate.Game.Bookmark{} = bookmark <- List.first(bookmarks) || {:error, :not_found},
         {:ok, branch} <- Ash.create(Fate.Game.Branch, %{
           name: branch_name,
           head_event_id: bookmark.event_id
         }, action: :create) do
      {:ok, [%{type: "text", text: "Created branch '#{branch_name}' (#{branch.id}) forked from bookmark '#{bookmark_name}'"}], state}
    else
      {:error, :not_found} ->
        {:error, %{code: -32000, message: "Bookmark '#{bookmark_name}' not found"}, state}

      {:error, reason} ->
        {:error, %{code: -32000, message: inspect(reason)}, state}
    end
  end

  def handle_call_tool("switch_branch", args, state) do
    branch =
      cond do
        args["branch_id"] ->
          case Ash.get(Fate.Game.Branch, args["branch_id"]) do
            {:ok, b} -> b
            _ -> nil
          end

        args["branch_name"] ->
          case Ash.read(Fate.Game.Branch, filter: [name: args["branch_name"]]) do
            {:ok, [b | _]} -> b
            _ -> nil
          end

        true ->
          nil
      end

    case branch do
      nil ->
        {:error, %{code: -32000, message: "Branch not found"}, state}

      b ->
        new_state = %{state | branch_id: b.id}
        {:ok, [%{type: "text", text: "Switched to branch '#{b.name}' (#{b.id})"}], new_state}
    end
  end

  def handle_call_tool("list_branches", _args, state) do
    case Ash.read(Fate.Game.Branch, load: [:head_event]) do
      {:ok, branches} ->
        list = Enum.map(branches, fn b ->
          %{
            id: b.id,
            name: b.name,
            status: b.status,
            head_event_id: b.head_event_id,
            head_timestamp: b.head_event && b.head_event.timestamp,
            current: b.id == state.branch_id
          }
        end)
        {:ok, [%{type: "text", text: Jason.encode!(list, pretty: true)}], state}

      _ ->
        {:ok, [%{type: "text", text: "[]"}], state}
    end
  end

  def handle_call_tool(tool_name, _args, state) do
    {:error, %{code: -32601, message: "Unknown tool: #{tool_name}"}, state}
  end

  # --- Resources ---

  @impl true
  def handle_list_resources(_cursor, state) do
    resources = [
      %{uri: "fate://game/state", name: "Game State", description: "Current derived game state", mimeType: "application/json"},
      %{uri: "fate://rules/ladder", name: "Fate Ladder", description: "The Fate ladder (+0 to +8)", mimeType: "application/json"}
    ]
    {:ok, resources, nil, state}
  end

  @impl true
  def handle_read_resource("fate://game/state", state) do
    case Engine.derive_state(state.branch_id) do
      {:ok, derived} ->
        summary = %{
          campaign_name: derived.campaign_name, system: derived.system,
          entities: derived.entities |> Map.values() |> Enum.map(&entity_summary/1),
          scenes: Enum.map(derived.scenes, &scene_summary/1)
        }
        {:ok, [%{type: "text", text: Jason.encode!(summary, pretty: true), mimeType: "application/json"}], state}

      _ ->
        {:ok, [%{type: "text", text: "{\"error\": \"Could not derive state\"}"}], state}
    end
  end

  def handle_read_resource("fate://rules/ladder", state) do
    ladder = [
      %{rating: 8, name: "Legendary"}, %{rating: 7, name: "Epic"},
      %{rating: 6, name: "Fantastic"}, %{rating: 5, name: "Superb"},
      %{rating: 4, name: "Great"}, %{rating: 3, name: "Good"},
      %{rating: 2, name: "Fair"}, %{rating: 1, name: "Average"},
      %{rating: 0, name: "Mediocre"}, %{rating: -1, name: "Terrible"}
    ]
    {:ok, [%{type: "text", text: Jason.encode!(ladder, pretty: true), mimeType: "application/json"}], state}
  end

  def handle_read_resource(_uri, state) do
    {:error, %{code: -32601, message: "Resource not found"}, state}
  end

  @impl true
  def handle_list_prompts(_cursor, state), do: {:ok, [], nil, state}

  @impl true
  def handle_get_prompt(_name, _args, state) do
    {:error, %{code: -32601, message: "No prompts"}, state}
  end

  # --- Serialization Helpers ---

  defp entity_summary(entity) do
    %{id: entity.id, name: entity.name, kind: entity.kind, fate_points: entity.fate_points, aspect_count: length(entity.aspects)}
  end

  defp entity_detail(entity) do
    %{
      id: entity.id, name: entity.name, kind: entity.kind, color: entity.color,
      fate_points: entity.fate_points, refresh: entity.refresh, mook_count: entity.mook_count,
      aspects: Enum.map(entity.aspects, fn a -> %{id: a.id, description: a.description, role: a.role, hidden: a.hidden, free_invokes: a.free_invokes} end),
      skills: entity.skills,
      stunts: Enum.map(entity.stunts, fn s -> %{id: s.id, name: s.name, effect: s.effect} end),
      stress_tracks: Enum.map(entity.stress_tracks, fn t -> %{label: t.label, boxes: t.boxes, checked: t.checked} end),
      consequences: Enum.map(entity.consequences, fn c -> %{id: c.id, severity: c.severity, shifts: c.shifts, aspect_text: c.aspect_text} end)
    }
  end

  defp scene_summary(nil), do: nil
  defp scene_summary(scene), do: %{id: scene.id, name: scene.name, status: scene.status, zone_count: length(scene.zones)}

  defp scene_detail(scene) do
    %{
      id: scene.id, name: scene.name, description: scene.description, status: scene.status,
      zones: Enum.map(scene.zones, fn z -> %{id: z.id, name: z.name, aspects: Enum.map(z.aspects, fn a -> %{description: a.description, role: a.role} end)} end),
      aspects: Enum.map(scene.aspects, fn a -> %{id: a.id, description: a.description, role: a.role, hidden: a.hidden} end)
    }
  end

  defp event_summary(event) do
    %{id: event.id, type: event.type, actor_id: event.actor_id, target_id: event.target_id, description: event.description}
  end
end
