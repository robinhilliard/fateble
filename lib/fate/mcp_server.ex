defmodule Fate.McpServer do
  @moduledoc """
  MCP server for AI-assisted Fate RPG prep.
  Mounted as an HTTP endpoint via ExMCP.HttpPlug on the Phoenix router.
  """

  use ExMCP.Server.Handler

  alias Fate.Engine

  @impl true
  def init(args) do
    bookmark_id = Keyword.get(args, :bookmark_id) || find_active_bookmark()
    {:ok, %{bookmark_id: bookmark_id}}
  end

  defp find_active_bookmark do
    require Ash.Query

    case Ash.read(
           Fate.Game.Bookmark
           |> Ash.Query.filter(status: :active)
           |> Ash.Query.sort(created_at: :desc)
         ) do
      {:ok, [latest | _]} -> latest.id
      _ -> nil
    end
  end

  @impl true
  def handle_initialize(_params, state) do
    {:ok,
     %{
       name: "fateble",
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
        description:
          "Get an overview of the current game state: campaign name, system, entities, scenes",
        inputSchema: %{type: "object", properties: %{}}
      },
      %{
        name: "list_entities",
        description: "List all entities with their name, kind, aspects, and fate points",
        inputSchema: %{
          type: "object",
          properties: %{
            kind: %{
              type: "string",
              description:
                "Filter by kind: pc, npc, mook_group, organization, vehicle, item, hazard, custom"
            }
          }
        }
      },
      %{
        name: "get_entity",
        description:
          "Get full details of a specific entity: aspects, skills, stunts, stress tracks, consequences",
        inputSchema: %{
          type: "object",
          properties: %{entity_id: %{type: "string", description: "The entity's ID"}},
          required: ["entity_id"]
        }
      },
      %{
        name: "list_scenes",
        description: "List all scenes with their status, zones, and situation aspects",
        inputSchema: %{type: "object", properties: %{}}
      },
      %{
        name: "get_action_log",
        description: "Get recent events from the action log",
        inputSchema: %{
          type: "object",
          properties: %{
            limit: %{type: "integer", description: "Max events to return (default 20)"}
          }
        }
      },
      %{
        name: "create_entity",
        description:
          "Create a new entity (character, NPC, organization, vehicle, etc.) with aspects, skills, stunts, and stress tracks",
        inputSchema: %{
          type: "object",
          properties: %{
            name: %{type: "string", description: "Entity name"},
            kind: %{
              type: "string",
              description:
                "Entity kind: pc, npc, mook_group, organization, vehicle, item, hazard, custom"
            },
            color: %{type: "string", description: "Hex color for visual coding (e.g. #dc2626)"},
            fate_points: %{type: "integer", description: "Starting fate points"},
            refresh: %{type: "integer", description: "Refresh rate"},
            mook_count: %{type: "integer", description: "Number of mooks (for mook_group)"},
            aspects: %{
              type: "array",
              description: "List of aspects",
              items: %{
                type: "object",
                properties: %{
                  description: %{type: "string"},
                  role: %{type: "string"},
                  hidden: %{type: "boolean"}
                },
                required: ["description"]
              }
            },
            skills: %{
              type: "object",
              description: "Skill ratings e.g. {\"Fight\": 4}",
              additionalProperties: %{type: "integer"}
            },
            stunts: %{
              type: "array",
              items: %{
                type: "object",
                properties: %{name: %{type: "string"}, effect: %{type: "string"}},
                required: ["name", "effect"]
              }
            },
            stress_tracks: %{
              type: "array",
              items: %{
                type: "object",
                properties: %{label: %{type: "string"}, boxes: %{type: "integer"}},
                required: ["label"]
              }
            },
            controller_id: %{
              type: "string",
              description: "Participant ID who controls this entity"
            },
            parent_entity_id: %{
              type: "string",
              description:
                "Parent entity ID for sub-entities (weapons, items attached to a character)"
            }
          },
          required: ["name", "kind"]
        }
      },
      %{
        name: "update_entity",
        description:
          "Modify an entity's properties (name, kind, color, fate_points, refresh, hidden)",
        inputSchema: %{
          type: "object",
          properties: %{
            entity_id: %{type: "string"},
            name: %{type: "string"},
            kind: %{type: "string"},
            color: %{type: "string"},
            fate_points: %{type: "integer"},
            refresh: %{type: "integer"},
            hidden: %{type: "boolean", description: "Hide or reveal entity from players"}
          },
          required: ["entity_id"]
        }
      },
      %{
        name: "add_aspect",
        description: "Add an aspect to an entity, scene, or zone",
        inputSchema: %{
          type: "object",
          properties: %{
            target_id: %{type: "string", description: "Entity, scene, or zone ID"},
            target_type: %{
              type: "string",
              description: "entity, scene, or zone (default: entity)"
            },
            description: %{type: "string", description: "The aspect text"},
            role: %{
              type: "string",
              description: "high_concept, trouble, additional, situation, boost, consequence"
            },
            hidden: %{type: "boolean"},
            free_invokes: %{type: "integer"}
          },
          required: ["target_id", "description"]
        }
      },
      %{
        name: "set_skill",
        description: "Set or update skill ratings on an entity. Pass multiple skills at once.",
        inputSchema: %{
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
        inputSchema: %{
          type: "object",
          properties: %{
            entity_id: %{type: "string"},
            name: %{type: "string"},
            effect: %{type: "string"}
          },
          required: ["entity_id", "name", "effect"]
        }
      },
      %{
        name: "create_bookmark",
        description:
          "Create a named bookmark on the current head event. Use to mark milestones like 'prep complete' or 'before the fight' for later return or what-if exploration.",
        inputSchema: %{
          type: "object",
          properties: %{
            name: %{type: "string", description: "Bookmark name"},
            description: %{
              type: "string",
              description: "Optional note about this point in the timeline"
            }
          },
          required: ["name"]
        }
      },
      %{
        name: "list_bookmarks",
        description: "List all named bookmarks",
        inputSchema: %{type: "object", properties: %{}}
      },
      %{
        name: "fork_from_bookmark",
        description:
          "Create a new bookmark forked from an existing one. Use for what-if exploration.",
        inputSchema: %{
          type: "object",
          properties: %{
            bookmark_name: %{type: "string", description: "Name of the bookmark to fork from"},
            new_name: %{type: "string", description: "Name for the new bookmark"}
          },
          required: ["bookmark_name", "new_name"]
        }
      },
      %{
        name: "switch_bookmark",
        description: "Switch the MCP server to operate on a different bookmark",
        inputSchema: %{
          type: "object",
          properties: %{
            bookmark_id: %{type: "string", description: "Bookmark ID to switch to"},
            bookmark_name: %{type: "string", description: "Or find by name instead of ID"}
          }
        }
      },
      %{
        name: "delete_bookmark",
        description: "Delete (archive) a bookmark by ID or name",
        inputSchema: %{
          type: "object",
          properties: %{
            bookmark_id: %{type: "string", description: "Bookmark ID"},
            bookmark_name: %{type: "string", description: "Or find by name"}
          }
        }
      },
      %{
        name: "create_scene",
        description: "Create a new scene with zones and situation aspects",
        inputSchema: %{
          type: "object",
          properties: %{
            name: %{type: "string"},
            description: %{type: "string"},
            zones: %{
              type: "array",
              items: %{type: "object", properties: %{name: %{type: "string"}}, required: ["name"]}
            },
            aspects: %{
              type: "array",
              items: %{
                type: "object",
                properties: %{description: %{type: "string"}, role: %{type: "string"}},
                required: ["description"]
              }
            }
          },
          required: ["name"]
        }
      },
      %{
        name: "remove_entity",
        description: "Remove an entity from the game",
        inputSchema: %{
          type: "object",
          properties: %{entity_id: %{type: "string"}},
          required: ["entity_id"]
        }
      },
      %{
        name: "stress_apply",
        description: "Check a stress box on an entity",
        inputSchema: %{
          type: "object",
          properties: %{
            entity_id: %{type: "string"},
            track_label: %{type: "string", description: "e.g. physical or mental"},
            box_index: %{type: "integer", description: "1-based box number"}
          },
          required: ["entity_id", "track_label", "box_index"]
        }
      },
      %{
        name: "consequence_take",
        description: "Apply a consequence to an entity",
        inputSchema: %{
          type: "object",
          properties: %{
            entity_id: %{type: "string"},
            severity: %{type: "string", description: "mild, moderate, severe, or extreme"},
            aspect_text: %{type: "string", description: "The consequence aspect text"}
          },
          required: ["entity_id", "severity", "aspect_text"]
        }
      },
      %{
        name: "concede",
        description: "An entity concedes a conflict",
        inputSchema: %{
          type: "object",
          properties: %{entity_id: %{type: "string"}},
          required: ["entity_id"]
        }
      },
      %{
        name: "entity_move",
        description: "Move an entity to a zone or remove from zone",
        inputSchema: %{
          type: "object",
          properties: %{
            entity_id: %{type: "string"},
            zone_id: %{type: "string", description: "Zone ID, or null to leave zone"}
          },
          required: ["entity_id"]
        }
      },
      %{
        name: "add_zone",
        description: "Add a zone to the active scene",
        inputSchema: %{
          type: "object",
          properties: %{
            scene_id: %{type: "string", description: "Scene ID to add zone to"},
            name: %{type: "string", description: "Zone name"},
            hidden: %{type: "boolean", description: "Start hidden (default true)"}
          },
          required: ["scene_id", "name"]
        }
      },
      %{
        name: "end_scene",
        description: "End a scene. Clears all stress and removes boosts.",
        inputSchema: %{
          type: "object",
          properties: %{
            scene_id: %{type: "string", description: "Scene ID to end"}
          },
          required: ["scene_id"]
        }
      },
      %{
        name: "fate_point_spend",
        description: "Spend a fate point from an entity",
        inputSchema: %{
          type: "object",
          properties: %{
            entity_id: %{type: "string"},
            amount: %{type: "integer", description: "Amount to spend (default 1)"}
          },
          required: ["entity_id"]
        }
      },
      %{
        name: "fate_point_earn",
        description: "Award a fate point to an entity",
        inputSchema: %{
          type: "object",
          properties: %{
            entity_id: %{type: "string"},
            amount: %{type: "integer", description: "Amount to earn (default 1)"}
          },
          required: ["entity_id"]
        }
      },
      %{
        name: "fate_point_refresh",
        description: "Refresh an entity's fate points to their refresh value",
        inputSchema: %{
          type: "object",
          properties: %{entity_id: %{type: "string"}},
          required: ["entity_id"]
        }
      },
      %{
        name: "consequence_recover",
        description: "Begin recovery on a consequence (rename it) or clear it entirely",
        inputSchema: %{
          type: "object",
          properties: %{
            entity_id: %{type: "string"},
            consequence_id: %{type: "string"},
            clear: %{type: "boolean", description: "true to remove, false to begin recovery"},
            new_aspect_text: %{
              type: "string",
              description: "New aspect text when beginning recovery"
            }
          },
          required: ["entity_id", "consequence_id"]
        }
      },
      %{
        name: "mook_eliminate",
        description: "Eliminate one or more mooks from a mook group",
        inputSchema: %{
          type: "object",
          properties: %{
            entity_id: %{type: "string"},
            count: %{type: "integer", description: "Number to eliminate (default 1)"}
          },
          required: ["entity_id"]
        }
      },
      %{
        name: "set_system",
        description:
          "Set the game system (core or accelerated). This determines the default skill list.",
        inputSchema: %{
          type: "object",
          properties: %{
            system: %{type: "string", description: "core or accelerated"},
            skill_list: %{
              type: "array",
              items: %{type: "string"},
              description: "Custom skill list (overrides system default)"
            }
          },
          required: ["system"]
        }
      },
      %{
        name: "remove_stunt",
        description: "Remove a stunt from an entity",
        inputSchema: %{
          type: "object",
          properties: %{
            entity_id: %{type: "string"},
            stunt_id: %{type: "string"}
          },
          required: ["entity_id", "stunt_id"]
        }
      },
      %{
        name: "remove_aspect",
        description: "Remove an aspect from an entity, scene, or zone",
        inputSchema: %{
          type: "object",
          properties: %{
            aspect_id: %{type: "string", description: "The aspect ID to remove"}
          },
          required: ["aspect_id"]
        }
      },
      %{
        name: "modify_zone",
        description: "Modify a zone's properties (name, hidden)",
        inputSchema: %{
          type: "object",
          properties: %{
            zone_id: %{type: "string"},
            name: %{type: "string"},
            hidden: %{type: "boolean"}
          },
          required: ["zone_id"]
        }
      },
      %{
        name: "modify_aspect",
        description: "Modify an aspect's properties (description, hidden, free_invokes)",
        inputSchema: %{
          type: "object",
          properties: %{
            aspect_id: %{type: "string"},
            description: %{type: "string"},
            hidden: %{type: "boolean"},
            free_invokes: %{type: "integer"}
          },
          required: ["aspect_id"]
        }
      },
      %{
        name: "invoke_aspect",
        description:
          "Invoke an aspect. If not free, spends a fate point from the invoking entity first.",
        inputSchema: %{
          type: "object",
          properties: %{
            entity_id: %{type: "string", description: "Entity invoking the aspect"},
            description: %{type: "string", description: "The aspect text being invoked"},
            free: %{
              type: "boolean",
              description: "true for free invoke, false to spend FP (default false)"
            }
          },
          required: ["entity_id", "description"]
        }
      },
      %{
        name: "compel_aspect",
        description: "Compel an aspect on an entity. The target earns a fate point.",
        inputSchema: %{
          type: "object",
          properties: %{
            entity_id: %{type: "string", description: "Entity being compelled"},
            aspect_id: %{type: "string", description: "The aspect being compelled"},
            description: %{type: "string", description: "What complication this causes"}
          },
          required: ["entity_id", "description"]
        }
      },
      %{
        name: "taken_out",
        description: "Mark an entity as taken out of a conflict",
        inputSchema: %{
          type: "object",
          properties: %{entity_id: %{type: "string"}},
          required: ["entity_id"]
        }
      },
      %{
        name: "clear_stress",
        description: "Clear all stress boxes on an entity",
        inputSchema: %{
          type: "object",
          properties: %{entity_id: %{type: "string"}},
          required: ["entity_id"]
        }
      },
      %{
        name: "delete_event",
        description: "Delete an event from the log. Reparents children to maintain the chain.",
        inputSchema: %{
          type: "object",
          properties: %{event_id: %{type: "string"}},
          required: ["event_id"]
        }
      },
      %{
        name: "scene_modify",
        description: "Edit a scene's name, description, or GM notes",
        inputSchema: %{
          type: "object",
          properties: %{
            scene_id: %{type: "string"},
            name: %{type: "string"},
            description: %{type: "string"},
            gm_notes: %{type: "string"}
          },
          required: ["scene_id"]
        }
      },
      %{
        name: "redirect_hit",
        description: "Redirect pending shifts from one entity to another",
        inputSchema: %{
          type: "object",
          properties: %{
            from_entity_id: %{type: "string", description: "Entity currently taking the hit"},
            to_entity_id: %{type: "string", description: "Entity to redirect shifts to"}
          },
          required: ["from_entity_id", "to_entity_id"]
        }
      },
      %{
        name: "add_note",
        description:
          "Add a freeform note to the game timeline. Use for narrative beats, character quotes, clues, acquisitions, memorable moments, or any other annotation. Optionally attach to an entity, scene, or zone.",
        inputSchema: %{
          type: "object",
          properties: %{
            text: %{type: "string", description: "The note text (required)"},
            target_id: %{
              type: "string",
              description: "Optional ID of an entity, scene, or zone to attach the note to"
            },
            target_type: %{
              type: "string",
              description: "Type of target: entity, scene, or zone. Required if target_id is set."
            }
          },
          required: ["text"]
        }
      },
      %{
        name: "search_notes",
        description:
          "Search notes in the current bookmark's timeline (not parent bookmarks). Returns matching notes with their text, target, and timestamp. Use to find clues, character quotes, narrative moments, inventory changes, etc.",
        inputSchema: %{
          type: "object",
          properties: %{
            query: %{
              type: "string",
              description:
                "Optional text to search for (case-insensitive substring match against note text)"
            },
            target_id: %{
              type: "string",
              description: "Optional: filter to notes attached to this entity/scene/zone ID"
            }
          }
        }
      },
      %{
        name: "roll_dice",
        description:
          "Roll 4 Fudge dice for an entity using a skill. Returns the dice results, skill rating, total, and optionally compares against a difficulty or opposition roll. Appends the roll as an event to the game log.",
        inputSchema: %{
          type: "object",
          properties: %{
            entity_id: %{type: "string", description: "The entity making the roll"},
            skill: %{type: "string", description: "The skill being used (e.g. Fight, Notice)"},
            action: %{
              type: "string",
              description: "The action type: attack, defend, overcome, create_advantage"
            },
            difficulty: %{
              type: "integer",
              description:
                "Optional fixed difficulty (for overcome). If omitted, the roll result is returned without comparison."
            },
            target_id: %{
              type: "string",
              description: "Optional target entity ID (for attack/create_advantage)"
            }
          },
          required: ["entity_id", "skill", "action"]
        }
      },
      %{
        name: "summarise_timeline",
        description: """
        Summarise the events in the current bookmark's timeline (since the last bookmark boundary — never include events from parent bookmarks).

        The style of summary depends on how the user asks:

        - If asked for "the story so far", "what happened in the narrative", "recap the adventure", or similar IN-WORLD requests: write the summary as if narrating a work of fiction. Use character names (not player names), describe actions dramatically, weave in notes and aspect descriptions as narrative colour. Do not mention game mechanics (dice rolls, fate points, stress boxes).

        - If asked about "the game", "what happened last session", "what did we do", or any question that BREAKS THE FOURTH WALL (e.g. mentioning player names, asking about mechanics): include game mechanics in the summary — mention dice results, fate point spends, consequences taken, stress applied, etc. alongside the narrative.

        Use notes (type: note) as primary sources for narrative detail — they contain character quotes, clues, memorable moments, and GM observations. Other events provide the mechanical backbone.

        SPOILER PREVENTION — critical rules:
        - NEVER reveal information from hidden entities, hidden aspects, hidden zones, or GM notes in narrative summaries. These are secrets the GM has not yet disclosed to the players.
        - Only describe what the players' characters would know or have witnessed — visible entities, revealed aspects, public scene descriptions.
        - If a GM asks privately (e.g. via a GM-only channel), you may include hidden information, but clearly mark it as GM-only.
        - When in doubt, omit rather than spoil. The GM controls the pace of revelation.
        """,
        inputSchema: %{
          type: "object",
          properties: %{
            style: %{
              type: "string",
              description:
                "Optional: 'narrative' for in-world fiction style, 'game' for mechanics-included style. If omitted, infer from the user's question."
            }
          }
        }
      }
    ]

    {:ok, tools, nil, state}
  end

  @impl true
  def handle_call_tool("get_game", _args, state) do
    with {:ok, derived} <- Engine.derive_state(state.bookmark_id) do
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

  @valid_entity_kinds ~w(pc npc mook_group organization vehicle item hazard custom)a

  def handle_call_tool("list_entities", args, state) do
    with {:ok, derived} <- Engine.derive_state(state.bookmark_id) do
      kind_filter = args["kind"]

      entities =
        derived.entities
        |> Map.values()
        |> then(fn entities ->
          if kind_filter do
            kind_atom = safe_to_atom(kind_filter, @valid_entity_kinds)
            if kind_atom, do: Enum.filter(entities, &(&1.kind == kind_atom)), else: entities
          else
            entities
          end
        end)
        |> Enum.map(&entity_detail/1)

      {:ok, [%{type: "text", text: Jason.encode!(entities, pretty: true)}], state}
    else
      _ -> {:error, %{code: -32000, message: "Failed to derive state"}, state}
    end
  end

  def handle_call_tool("get_entity", %{"entity_id" => entity_id}, state) do
    with {:ok, derived} <- Engine.derive_state(state.bookmark_id) do
      case Map.get(derived.entities, entity_id) do
        nil ->
          {:ok, [%{type: "text", text: "Entity not found: #{entity_id}"}], state}

        entity ->
          {:ok, [%{type: "text", text: Jason.encode!(entity_detail(entity), pretty: true)}],
           state}
      end
    else
      _ -> {:error, %{code: -32000, message: "Failed to derive state"}, state}
    end
  end

  def handle_call_tool("list_scenes", _args, state) do
    with {:ok, derived} <- Engine.derive_state(state.bookmark_id) do
      scenes = Enum.map(derived.scenes, &scene_detail/1)
      {:ok, [%{type: "text", text: Jason.encode!(scenes, pretty: true)}], state}
    else
      _ -> {:error, %{code: -32000, message: "Failed to derive state"}, state}
    end
  end

  def handle_call_tool("get_action_log", args, state) do
    limit = args["limit"] || 20

    with {:ok, events} <- Engine.load_player_events(state.bookmark_id) do
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
      "name" => args["name"],
      "kind" => args["kind"],
      "color" => args["color"] || "#6b7280",
      "fate_points" => args["fate_points"],
      "refresh" => args["refresh"],
      "mook_count" => args["mook_count"],
      "controller_id" => args["controller_id"],
      "parent_entity_id" => args["parent_entity_id"],
      "aspects" => args["aspects"] || [],
      "skills" => args["skills"] || %{},
      "stunts" => args["stunts"] || [],
      "stress_tracks" => args["stress_tracks"] || []
    }

    case Engine.append_event(state.bookmark_id, %{
           type: :entity_create,
           description: "Create #{args["name"]} (#{args["kind"]})",
           detail: detail
         }) do
      {:ok, _state, _event} ->
        {:ok,
         [
           %{
             type: "text",
             text: "Created '#{args["name"]}' (#{args["kind"]}) with ID #{entity_id}"
           }
         ], state}

      {:error, reason} ->
        {:error, %{code: -32000, message: "Failed: #{inspect(reason)}"}, state}
    end
  end

  def handle_call_tool("update_entity", args, state) do
    entity_id = args["entity_id"]
    detail = Map.drop(args, ["entity_id"]) |> Map.put("entity_id", entity_id)

    case Engine.append_event(state.bookmark_id, %{
           type: :entity_modify,
           target_id: entity_id,
           description: "Modify entity #{entity_id}",
           detail: detail
         }) do
      {:ok, _, _} -> {:ok, [%{type: "text", text: "Updated entity #{entity_id}"}], state}
      {:error, reason} -> {:error, %{code: -32000, message: inspect(reason)}, state}
    end
  end

  def handle_call_tool("add_aspect", args, state) do
    detail = %{
      "target_id" => args["target_id"],
      "target_type" => args["target_type"] || "entity",
      "description" => args["description"],
      "role" => args["role"] || "additional",
      "hidden" => args["hidden"] || false,
      "free_invokes" => args["free_invokes"] || 0
    }

    case Engine.append_event(state.bookmark_id, %{
           type: :aspect_create,
           target_id: args["target_id"],
           description: "Add aspect: #{args["description"]}",
           detail: detail
         }) do
      {:ok, _, _} ->
        {:ok,
         [%{type: "text", text: "Added aspect '#{args["description"]}' to #{args["target_id"]}"}],
         state}

      {:error, reason} ->
        {:error, %{code: -32000, message: inspect(reason)}, state}
    end
  end

  def handle_call_tool("set_skill", %{"entity_id" => entity_id, "skills" => skills}, state) do
    results =
      Enum.map(skills, fn {skill, rating} ->
        Engine.append_event(state.bookmark_id, %{
          type: :skill_set,
          target_id: entity_id,
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
    case Engine.append_event(state.bookmark_id, %{
           type: :stunt_add,
           target_id: args["entity_id"],
           description: "Add stunt: #{args["name"]}",
           detail: %{
             "entity_id" => args["entity_id"],
             "name" => args["name"],
             "effect" => args["effect"]
           }
         }) do
      {:ok, _, _} ->
        {:ok, [%{type: "text", text: "Added stunt '#{args["name"]}' to #{args["entity_id"]}"}],
         state}

      {:error, reason} ->
        {:error, %{code: -32000, message: inspect(reason)}, state}
    end
  end

  def handle_call_tool("create_scene", args, state) do
    detail = %{
      "scene_id" => Ash.UUID.generate(),
      "name" => args["name"],
      "description" => args["description"],
      "zones" => args["zones"] || [],
      "aspects" =>
        Enum.map(args["aspects"] || [], fn a -> Map.put_new(a, "role", "situation") end)
    }

    case Engine.append_event(state.bookmark_id, %{
           type: :scene_start,
           description: "Start scene: #{args["name"]}",
           detail: detail
         }) do
      {:ok, _, _} ->
        {:ok,
         [
           %{
             type: "text",
             text: "Created scene '#{args["name"]}' with #{length(detail["zones"])} zones"
           }
         ], state}

      {:error, reason} ->
        {:error, %{code: -32000, message: inspect(reason)}, state}
    end
  end

  def handle_call_tool("create_bookmark", args, state) do
    with {:ok, parent} when parent != nil <- Fate.Game.get_bookmark(state.bookmark_id),
         {:ok, bmk_event} <-
           Fate.Game.append_event(%{
             parent_id: parent.head_event_id,
             type: :bookmark_create,
             description: args["name"],
             detail: %{"name" => args["name"]}
           }),
         {:ok, bookmark} <-
           Fate.Game.create_bookmark(%{
             name: args["name"],
             description: args["description"],
             head_event_id: bmk_event.id,
             parent_bookmark_id: parent.id
           }) do
      {:ok, [%{type: "text", text: "Created bookmark '#{args["name"]}' (#{bookmark.id})"}], state}
    else
      {:error, reason} -> {:error, %{code: -32000, message: inspect(reason)}, state}
      _ -> {:error, %{code: -32000, message: "Failed to create bookmark"}, state}
    end
  end

  def handle_call_tool("list_bookmarks", _args, state) do
    case Ash.read(Fate.Game.Bookmark, load: [:head_event]) do
      {:ok, bookmarks} ->
        list =
          Enum.map(bookmarks, fn b ->
            %{
              id: b.id,
              name: b.name,
              description: b.description,
              head_event_id: b.head_event_id,
              parent_bookmark_id: b.parent_bookmark_id,
              status: b.status,
              created_at: b.created_at,
              current: b.id == state.bookmark_id
            }
          end)

        {:ok, [%{type: "text", text: Jason.encode!(list, pretty: true)}], state}

      _ ->
        {:ok, [%{type: "text", text: "[]"}], state}
    end
  end

  def handle_call_tool("fork_from_bookmark", args, state) do
    bookmark_name = args["bookmark_name"]
    new_name = args["new_name"] || "Fork: #{bookmark_name}"

    with {:ok, bookmarks} <- Ash.read(Fate.Game.Bookmark, filter: [name: bookmark_name]),
         %Fate.Game.Bookmark{} = parent <- List.first(bookmarks) || {:error, :not_found},
         {:ok, bmk_event} <-
           Fate.Game.append_event(%{
             parent_id: parent.head_event_id,
             type: :bookmark_create,
             description: new_name,
             detail: %{"name" => new_name}
           }),
         {:ok, new_bm} <-
           Fate.Game.create_bookmark(%{
             name: new_name,
             head_event_id: bmk_event.id,
             parent_bookmark_id: parent.id
           }) do
      {:ok,
       [
         %{
           type: "text",
           text: "Created bookmark '#{new_name}' (#{new_bm.id}) forked from '#{bookmark_name}'"
         }
       ], state}
    else
      {:error, :not_found} ->
        {:error, %{code: -32000, message: "Bookmark '#{bookmark_name}' not found"}, state}

      {:error, reason} ->
        {:error, %{code: -32000, message: inspect(reason)}, state}
    end
  end

  def handle_call_tool("switch_bookmark", args, state) do
    bookmark =
      cond do
        args["bookmark_id"] ->
          case Fate.Game.get_bookmark(args["bookmark_id"]) do
            {:ok, b} -> b
            _ -> nil
          end

        args["bookmark_name"] ->
          case Ash.read(Fate.Game.Bookmark, filter: [name: args["bookmark_name"]]) do
            {:ok, [b | _]} -> b
            _ -> nil
          end

        true ->
          nil
      end

    case bookmark do
      nil ->
        {:error, %{code: -32000, message: "Bookmark not found"}, state}

      b ->
        new_state = %{state | bookmark_id: b.id}
        {:ok, [%{type: "text", text: "Switched to bookmark '#{b.name}' (#{b.id})"}], new_state}
    end
  end

  def handle_call_tool("remove_entity", %{"entity_id" => entity_id}, state) do
    case Engine.append_event(state.bookmark_id, %{
           type: :entity_remove,
           target_id: entity_id,
           description: "Remove entity"
         }) do
      {:ok, _state, _event} -> {:ok, [%{type: "text", text: "Entity removed"}], state}
      _ -> {:error, %{code: -32000, message: "Failed to remove entity"}, state}
    end
  end

  def handle_call_tool(
        "stress_apply",
        %{"entity_id" => entity_id, "track_label" => track_label, "box_index" => box_index},
        state
      ) do
    case Engine.append_event(state.bookmark_id, %{
           type: :stress_apply,
           target_id: entity_id,
           description: "Stress #{track_label} box #{box_index}",
           detail: %{
             "entity_id" => entity_id,
             "track_label" => track_label,
             "box_index" => box_index,
             "shifts_absorbed" => box_index
           }
         }) do
      {:ok, _state, _event} ->
        {:ok, [%{type: "text", text: "Stress applied: #{track_label} box #{box_index}"}], state}

      _ ->
        {:error, %{code: -32000, message: "Failed to apply stress"}, state}
    end
  end

  def handle_call_tool(
        "consequence_take",
        %{"entity_id" => entity_id, "severity" => severity, "aspect_text" => aspect_text},
        state
      ) do
    case Engine.append_event(state.bookmark_id, %{
           type: :consequence_take,
           target_id: entity_id,
           description: "#{severity}: #{aspect_text}",
           detail: %{
             "entity_id" => entity_id,
             "severity" => severity,
             "aspect_text" => aspect_text
           }
         }) do
      {:ok, _state, _event} ->
        {:ok, [%{type: "text", text: "Consequence taken: #{severity} — #{aspect_text}"}], state}

      _ ->
        {:error, %{code: -32000, message: "Failed to take consequence"}, state}
    end
  end

  def handle_call_tool("concede", %{"entity_id" => entity_id}, state) do
    entity_name = entity_name_from_state(state.bookmark_id, entity_id)

    case Engine.append_event(state.bookmark_id, %{
           type: :concede,
           actor_id: entity_id,
           description: "#{entity_name} concedes"
         }) do
      {:ok, _state, _event} -> {:ok, [%{type: "text", text: "#{entity_name} conceded"}], state}
      _ -> {:error, %{code: -32000, message: "Failed to concede"}, state}
    end
  end

  def handle_call_tool("entity_move", %{"entity_id" => entity_id} = args, state) do
    zone_id = args["zone_id"]

    case Engine.append_event(state.bookmark_id, %{
           type: :entity_move,
           actor_id: entity_id,
           description: if(zone_id, do: "Move to zone", else: "Leave zone"),
           detail: %{"entity_id" => entity_id, "zone_id" => zone_id}
         }) do
      {:ok, _state, _event} ->
        {:ok, [%{type: "text", text: if(zone_id, do: "Moved to zone", else: "Left zone")}], state}

      _ ->
        {:error, %{code: -32000, message: "Failed to move entity"}, state}
    end
  end

  def handle_call_tool("add_zone", %{"scene_id" => scene_id, "name" => name} = args, state) do
    case Engine.append_event(state.bookmark_id, %{
           type: :zone_create,
           description: "Create zone: #{name}",
           detail: %{
             "scene_id" => scene_id,
             "zone_id" => Ash.UUID.generate(),
             "name" => name,
             "hidden" => Map.get(args, "hidden", true)
           }
         }) do
      {:ok, _, _} -> {:ok, [%{type: "text", text: "Created zone '#{name}'"}], state}
      {:error, reason} -> {:error, %{code: -32000, message: inspect(reason)}, state}
    end
  end

  def handle_call_tool("end_scene", %{"scene_id" => scene_id}, state) do
    case Engine.append_event(state.bookmark_id, %{
           type: :scene_end,
           description: "End scene",
           detail: %{"scene_id" => scene_id}
         }) do
      {:ok, _, _} -> {:ok, [%{type: "text", text: "Scene ended"}], state}
      {:error, reason} -> {:error, %{code: -32000, message: inspect(reason)}, state}
    end
  end

  def handle_call_tool("fate_point_spend", %{"entity_id" => entity_id} = args, state) do
    amount = args["amount"] || 1

    case Engine.append_event(state.bookmark_id, %{
           type: :fate_point_spend,
           target_id: entity_id,
           description: "Spend #{amount} fate point(s)",
           detail: %{"entity_id" => entity_id, "amount" => amount}
         }) do
      {:ok, _, _} -> {:ok, [%{type: "text", text: "Spent #{amount} FP"}], state}
      {:error, reason} -> {:error, %{code: -32000, message: inspect(reason)}, state}
    end
  end

  def handle_call_tool("fate_point_earn", %{"entity_id" => entity_id} = args, state) do
    amount = args["amount"] || 1

    case Engine.append_event(state.bookmark_id, %{
           type: :fate_point_earn,
           target_id: entity_id,
           description: "Earn #{amount} fate point(s)",
           detail: %{"entity_id" => entity_id, "amount" => amount}
         }) do
      {:ok, _, _} -> {:ok, [%{type: "text", text: "Earned #{amount} FP"}], state}
      {:error, reason} -> {:error, %{code: -32000, message: inspect(reason)}, state}
    end
  end

  def handle_call_tool("fate_point_refresh", %{"entity_id" => entity_id}, state) do
    case Engine.append_event(state.bookmark_id, %{
           type: :fate_point_refresh,
           target_id: entity_id,
           description: "Refresh fate points",
           detail: %{"entity_id" => entity_id}
         }) do
      {:ok, _, _} -> {:ok, [%{type: "text", text: "Fate points refreshed"}], state}
      {:error, reason} -> {:error, %{code: -32000, message: inspect(reason)}, state}
    end
  end

  def handle_call_tool(
        "consequence_recover",
        %{"entity_id" => entity_id, "consequence_id" => consequence_id} = args,
        state
      ) do
    clear = args["clear"] || false

    case Engine.append_event(state.bookmark_id, %{
           type: :consequence_recover,
           target_id: entity_id,
           description: if(clear, do: "Clear consequence", else: "Begin recovery"),
           detail: %{
             "entity_id" => entity_id,
             "consequence_id" => consequence_id,
             "clear" => clear,
             "new_aspect_text" => args["new_aspect_text"]
           }
         }) do
      {:ok, _, _} ->
        msg = if clear, do: "Consequence cleared", else: "Recovery started"
        {:ok, [%{type: "text", text: msg}], state}

      {:error, reason} ->
        {:error, %{code: -32000, message: inspect(reason)}, state}
    end
  end

  def handle_call_tool("set_system", %{"system" => system} = args, state) do
    detail = %{"system" => system}

    detail =
      if args["skill_list"], do: Map.put(detail, "skill_list", args["skill_list"]), else: detail

    case Engine.append_event(state.bookmark_id, %{
           type: :set_system,
           description: "Set system: #{system}",
           detail: detail
         }) do
      {:ok, _, _} -> {:ok, [%{type: "text", text: "System set to #{system}"}], state}
      {:error, reason} -> {:error, %{code: -32000, message: inspect(reason)}, state}
    end
  end

  def handle_call_tool("remove_stunt", %{"entity_id" => entity_id, "stunt_id" => stunt_id}, state) do
    case Engine.append_event(state.bookmark_id, %{
           type: :stunt_remove,
           target_id: entity_id,
           description: "Remove stunt",
           detail: %{"entity_id" => entity_id, "stunt_id" => stunt_id}
         }) do
      {:ok, _, _} -> {:ok, [%{type: "text", text: "Stunt removed"}], state}
      {:error, reason} -> {:error, %{code: -32000, message: inspect(reason)}, state}
    end
  end

  def handle_call_tool("remove_aspect", %{"aspect_id" => aspect_id}, state) do
    case Engine.append_event(state.bookmark_id, %{
           type: :aspect_remove,
           description: "Remove aspect",
           detail: %{"aspect_id" => aspect_id}
         }) do
      {:ok, _, _} -> {:ok, [%{type: "text", text: "Aspect removed"}], state}
      {:error, reason} -> {:error, %{code: -32000, message: inspect(reason)}, state}
    end
  end

  def handle_call_tool("modify_zone", %{"zone_id" => zone_id} = args, state) do
    detail = pick_present_keys(%{"zone_id" => zone_id}, args, ~w(name hidden))

    case Engine.append_event(state.bookmark_id, %{
           type: :zone_modify,
           description: "Modify zone",
           detail: detail
         }) do
      {:ok, _, _} -> {:ok, [%{type: "text", text: "Zone updated"}], state}
      {:error, reason} -> {:error, %{code: -32000, message: inspect(reason)}, state}
    end
  end

  def handle_call_tool("modify_aspect", %{"aspect_id" => aspect_id} = args, state) do
    detail =
      pick_present_keys(%{"aspect_id" => aspect_id}, args, ~w(description hidden free_invokes))

    case Engine.append_event(state.bookmark_id, %{
           type: :aspect_modify,
           description: "Modify aspect",
           detail: detail
         }) do
      {:ok, _, _} -> {:ok, [%{type: "text", text: "Aspect updated"}], state}
      {:error, reason} -> {:error, %{code: -32000, message: inspect(reason)}, state}
    end
  end

  def handle_call_tool(
        "invoke_aspect",
        %{"entity_id" => entity_id, "description" => description} = args,
        state
      ) do
    free = args["free"] || false

    unless free do
      Engine.append_event(state.bookmark_id, %{
        type: :fate_point_spend,
        target_id: entity_id,
        description: "Spend FP to invoke: #{description}",
        detail: %{"entity_id" => entity_id, "amount" => 1}
      })
    end

    case Engine.append_event(state.bookmark_id, %{
           type: :invoke,
           actor_id: entity_id,
           description: "Invoke: #{description}#{if free, do: " (free)", else: " (FP)"}",
           detail: %{"description" => description, "free" => free}
         }) do
      {:ok, _, _} -> {:ok, [%{type: "text", text: "Invoked: #{description}"}], state}
      {:error, reason} -> {:error, %{code: -32000, message: inspect(reason)}, state}
    end
  end

  def handle_call_tool(
        "compel_aspect",
        %{"entity_id" => entity_id, "description" => description} = args,
        state
      ) do
    entity_name = entity_name_from_state(state.bookmark_id, entity_id)

    Engine.append_event(state.bookmark_id, %{
      type: :aspect_compel,
      target_id: entity_id,
      description: "Compel #{entity_name}: #{description}",
      detail: %{
        "aspect_id" => args["aspect_id"],
        "description" => description,
        "accepted" => true
      }
    })

    case Engine.append_event(state.bookmark_id, %{
           type: :fate_point_earn,
           target_id: entity_id,
           description: "#{entity_name} earns FP from compel: #{description}",
           detail: %{"entity_id" => entity_id, "amount" => 1}
         }) do
      {:ok, _, _} ->
        {:ok, [%{type: "text", text: "Compelled: #{description}. #{entity_id} earned 1 FP."}],
         state}

      {:error, reason} ->
        {:error, %{code: -32000, message: inspect(reason)}, state}
    end
  end

  def handle_call_tool("taken_out", %{"entity_id" => entity_id}, state) do
    entity_name = entity_name_from_state(state.bookmark_id, entity_id)

    case Engine.append_event(state.bookmark_id, %{
           type: :taken_out,
           target_id: entity_id,
           description: "#{entity_name} taken out"
         }) do
      {:ok, _, _} -> {:ok, [%{type: "text", text: "#{entity_name} taken out"}], state}
      {:error, reason} -> {:error, %{code: -32000, message: inspect(reason)}, state}
    end
  end

  def handle_call_tool("clear_stress", %{"entity_id" => entity_id}, state) do
    case Engine.append_event(state.bookmark_id, %{
           type: :stress_clear,
           target_id: entity_id,
           description: "Clear all stress"
         }) do
      {:ok, _, _} -> {:ok, [%{type: "text", text: "Stress cleared"}], state}
      {:error, reason} -> {:error, %{code: -32000, message: inspect(reason)}, state}
    end
  end

  def handle_call_tool("delete_event", %{"event_id" => event_id}, state) do
    case Fate.Game.Events.delete(event_id, state.bookmark_id) do
      :ok -> {:ok, [%{type: "text", text: "Event deleted"}], state}
      {:error, reason} -> {:error, %{code: -32000, message: "Failed: #{inspect(reason)}"}, state}
    end
  end

  def handle_call_tool("mook_eliminate", %{"entity_id" => entity_id} = args, state) do
    count = args["count"] || 1

    case Engine.append_event(state.bookmark_id, %{
           type: :mook_eliminate,
           target_id: entity_id,
           description: "Eliminate #{count} mook(s)",
           detail: %{"entity_id" => entity_id, "count" => count}
         }) do
      {:ok, _, _} -> {:ok, [%{type: "text", text: "#{count} mook(s) eliminated"}], state}
      {:error, reason} -> {:error, %{code: -32000, message: inspect(reason)}, state}
    end
  end

  def handle_call_tool("scene_modify", %{"scene_id" => scene_id} = args, state) do
    detail = pick_present_keys(%{"scene_id" => scene_id}, args, ~w(name description gm_notes))

    case Engine.append_event(state.bookmark_id, %{
           type: :scene_modify,
           description: "Edit scene",
           detail: detail
         }) do
      {:ok, _, _} -> {:ok, [%{type: "text", text: "Scene updated"}], state}
      {:error, reason} -> {:error, %{code: -32000, message: inspect(reason)}, state}
    end
  end

  def handle_call_tool(
        "redirect_hit",
        %{"from_entity_id" => from_id, "to_entity_id" => to_id},
        state
      ) do
    case Engine.append_event(state.bookmark_id, %{
           type: :redirect_hit,
           actor_id: from_id,
           target_id: to_id,
           description: "Redirect hit",
           detail: %{"from_entity_id" => from_id, "to_entity_id" => to_id}
         }) do
      {:ok, _, _} -> {:ok, [%{type: "text", text: "Hit redirected"}], state}
      {:error, reason} -> {:error, %{code: -32000, message: inspect(reason)}, state}
    end
  end

  def handle_call_tool("delete_bookmark", args, state) do
    bookmark =
      cond do
        args["bookmark_id"] ->
          case Fate.Game.get_bookmark(args["bookmark_id"]) do
            {:ok, b} -> b
            _ -> nil
          end

        args["bookmark_name"] ->
          case Ash.read(Fate.Game.Bookmark, filter: [name: args["bookmark_name"]]) do
            {:ok, [b | _]} -> b
            _ -> nil
          end

        true ->
          nil
      end

    case bookmark do
      nil ->
        {:error, %{code: -32000, message: "Bookmark not found"}, state}

      b ->
        case Fate.Game.set_status(b, %{status: :archived}) do
          {:ok, _} ->
            new_state = if state.bookmark_id == b.id, do: %{state | bookmark_id: nil}, else: state
            {:ok, [%{type: "text", text: "Archived bookmark '#{b.name}' (#{b.id})"}], new_state}

          {:error, reason} ->
            {:error, %{code: -32000, message: "Failed to archive: #{inspect(reason)}"}, state}
        end
    end
  end

  def handle_call_tool("add_note", %{"text" => text} = args, state) do
    detail =
      %{"text" => text}
      |> then(fn d ->
        if args["target_id"],
          do:
            Map.merge(d, %{
              "target_id" => args["target_id"],
              "target_type" => args["target_type"] || "entity"
            }),
          else: d
      end)

    with {:ok, _state, _event} <-
           Engine.append_event(state.bookmark_id, %{
             type: :note,
             target_id: args["target_id"],
             description: text,
             detail: detail
           }) do
      {:ok, [%{type: "text", text: "Note added: #{String.slice(text, 0..80)}"}], state}
    end
  end

  def handle_call_tool("search_notes", args, state) do
    with {:ok, events} <- Engine.load_player_events(state.bookmark_id) do
      query = args["query"]
      target_id = args["target_id"]
      query_lower = query && String.downcase(query)

      notes =
        events
        |> Enum.filter(&(&1.type == :note))
        |> Enum.filter(fn event ->
          text = get_in(event.detail, ["text"]) || event.description || ""

          matches_query =
            if query_lower,
              do: String.contains?(String.downcase(text), query_lower),
              else: true

          matches_target =
            if target_id, do: event.target_id == target_id, else: true

          matches_query && matches_target
        end)
        |> Enum.map(fn event ->
          %{
            text: get_in(event.detail, ["text"]) || event.description,
            target_id: event.target_id,
            target_type: get_in(event.detail, ["target_type"]),
            timestamp: event.timestamp
          }
        end)

      result = Jason.encode!(notes, pretty: true)

      {:ok, [%{type: "text", text: "Found #{length(notes)} notes:\n#{result}"}], state}
    else
      _ -> {:ok, [%{type: "text", text: "No notes found (bookmark not loaded)"}], state}
    end
  end

  def handle_call_tool(
        "roll_dice",
        %{"entity_id" => entity_id, "skill" => skill, "action" => action} = args,
        state
      ) do
    with {:ok, derived} <- Engine.derive_state(state.bookmark_id),
         entity when entity != nil <- Map.get(derived.entities, entity_id) do
      dice = for _ <- 1..4, do: Enum.random([-1, 0, 1])
      dice_sum = Enum.sum(dice)
      skill_rating = Map.get(entity.skills, skill, 0)
      total = dice_sum + skill_rating

      event_type =
        case action do
          "attack" -> :roll_attack
          "defend" -> :roll_defend
          "overcome" -> :roll_overcome
          "create_advantage" -> :roll_create_advantage
          _ -> :roll_overcome
        end

      dice_display =
        Enum.map(dice, fn
          -1 -> "-"
          0 -> "0"
          1 -> "+"
        end)
        |> Enum.join()

      description =
        "#{entity.name} rolls #{skill} [#{dice_display}] = #{if total >= 0, do: "+"}#{total}"

      detail = %{
        "entity_id" => entity_id,
        "skill" => skill,
        "skill_rating" => skill_rating,
        "fudge_dice" => dice,
        "raw_total" => total
      }

      detail =
        if args["difficulty"], do: Map.put(detail, "difficulty", args["difficulty"]), else: detail

      Engine.append_event(state.bookmark_id, %{
        type: event_type,
        actor_id: entity_id,
        target_id: args["target_id"],
        description: description,
        detail: detail
      })

      result = %{
        entity: entity.name,
        skill: skill,
        skill_rating: skill_rating,
        dice: dice,
        dice_sum: dice_sum,
        total: total,
        action: action
      }

      result =
        if args["difficulty"] do
          shifts = total - args["difficulty"]

          outcome =
            cond do
              shifts >= 3 -> "succeed_with_style"
              shifts > 0 -> "succeed"
              shifts == 0 -> "tie"
              true -> "fail"
            end

          Map.merge(result, %{difficulty: args["difficulty"], shifts: shifts, outcome: outcome})
        else
          result
        end

      {:ok, [%{type: "text", text: Jason.encode!(result, pretty: true)}], state}
    else
      nil -> {:error, %{code: -32000, message: "Entity not found"}, state}
      error -> {:error, %{code: -32000, message: "Error: #{inspect(error)}"}, state}
    end
  end

  def handle_call_tool("summarise_timeline", args, state) do
    style = args["style"] || "narrative"

    with {:ok, events} <- Engine.load_player_events(state.bookmark_id),
         {:ok, derived} <- Engine.derive_state(state.bookmark_id) do
      event_summaries = Enum.map(events, &event_summary/1)

      notes =
        events
        |> Enum.filter(&(&1.type == :note))
        |> Enum.map(fn e ->
          %{
            text: get_in(e.detail, ["text"]) || e.description,
            target_id: e.target_id,
            timestamp: e.timestamp
          }
        end)

      entity_names =
        derived.entities
        |> Map.values()
        |> Enum.map(fn e -> %{name: e.name, kind: e.kind} end)

      scene_names =
        derived.scenes
        |> Enum.map(fn s -> %{name: s.name, status: s.status} end)

      payload = %{
        style: style,
        total_events: length(events),
        events: event_summaries,
        notes: notes,
        entities: entity_names,
        scenes: scene_names
      }

      {:ok, [%{type: "text", text: Jason.encode!(payload, pretty: true)}], state}
    else
      _ -> {:error, %{code: -32000, message: "Failed to load timeline"}, state}
    end
  end

  def handle_call_tool(tool_name, _args, state) do
    {:error, %{code: -32601, message: "Unknown tool: #{tool_name}"}, state}
  end

  # --- Resources ---

  @impl true
  def handle_list_resources(_cursor, state) do
    resources = [
      %{
        uri: "fate://game/state",
        name: "Game State",
        description: "Current derived game state",
        mimeType: "application/json"
      },
      %{
        uri: "fate://rules/ladder",
        name: "Fate Ladder",
        description: "The Fate ladder (+0 to +8)",
        mimeType: "application/json"
      }
    ]

    {:ok, resources, nil, state}
  end

  @impl true
  def handle_read_resource("fate://game/state", state) do
    case Engine.derive_state(state.bookmark_id) do
      {:ok, derived} ->
        summary = %{
          campaign_name: derived.campaign_name,
          system: derived.system,
          entities: derived.entities |> Map.values() |> Enum.map(&entity_summary/1),
          scenes: Enum.map(derived.scenes, &scene_summary/1)
        }

        {:ok,
         [
           %{
             type: "text",
             text: Jason.encode!(summary, pretty: true),
             mimeType: "application/json"
           }
         ], state}

      _ ->
        {:ok, [%{type: "text", text: "{\"error\": \"Could not derive state\"}"}], state}
    end
  end

  def handle_read_resource("fate://rules/ladder", state) do
    ladder = [
      %{rating: 8, name: "Legendary"},
      %{rating: 7, name: "Epic"},
      %{rating: 6, name: "Fantastic"},
      %{rating: 5, name: "Superb"},
      %{rating: 4, name: "Great"},
      %{rating: 3, name: "Good"},
      %{rating: 2, name: "Fair"},
      %{rating: 1, name: "Average"},
      %{rating: 0, name: "Mediocre"},
      %{rating: -1, name: "Terrible"}
    ]

    {:ok,
     [%{type: "text", text: Jason.encode!(ladder, pretty: true), mimeType: "application/json"}],
     state}
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

  defp safe_to_atom(string, valid_atoms) do
    Enum.find(valid_atoms, fn atom -> to_string(atom) == string end)
  end

  defp entity_summary(entity) do
    %{
      id: entity.id,
      name: entity.name,
      kind: entity.kind,
      fate_points: entity.fate_points,
      aspect_count: length(entity.aspects)
    }
  end

  defp entity_detail(entity) do
    %{
      id: entity.id,
      name: entity.name,
      kind: entity.kind,
      color: entity.color,
      fate_points: entity.fate_points,
      refresh: entity.refresh,
      mook_count: entity.mook_count,
      aspects:
        Enum.map(entity.aspects, fn a ->
          %{
            id: a.id,
            description: a.description,
            role: a.role,
            hidden: a.hidden,
            free_invokes: a.free_invokes
          }
        end),
      skills: entity.skills,
      stunts: Enum.map(entity.stunts, fn s -> %{id: s.id, name: s.name, effect: s.effect} end),
      stress_tracks:
        Enum.map(entity.stress_tracks, fn t ->
          %{label: t.label, boxes: t.boxes, checked: t.checked}
        end),
      consequences:
        Enum.map(entity.consequences, fn c ->
          %{id: c.id, severity: c.severity, shifts: c.shifts, aspect_text: c.aspect_text}
        end)
    }
  end

  defp scene_summary(nil), do: nil

  defp scene_summary(scene),
    do: %{id: scene.id, name: scene.name, status: scene.status, zone_count: length(scene.zones)}

  defp scene_detail(scene) do
    %{
      id: scene.id,
      name: scene.name,
      description: scene.description,
      status: scene.status,
      zones:
        Enum.map(scene.zones, fn z ->
          %{
            id: z.id,
            name: z.name,
            aspects: Enum.map(z.aspects, fn a -> %{description: a.description, role: a.role} end)
          }
        end),
      aspects:
        Enum.map(scene.aspects, fn a ->
          %{id: a.id, description: a.description, role: a.role, hidden: a.hidden}
        end)
    }
  end

  defp event_summary(event) do
    %{
      id: event.id,
      type: event.type,
      actor_id: event.actor_id,
      target_id: event.target_id,
      description: event.description
    }
  end

  defp entity_name_from_state(bookmark_id, entity_id) do
    case Engine.derive_state(bookmark_id) do
      {:ok, derived} ->
        case Map.get(derived.entities, entity_id) do
          nil -> "entity"
          e -> e.name
        end

      _ ->
        "entity"
    end
  end

  defp pick_present_keys(base_map, source_map, keys) do
    Enum.reduce(keys, base_map, fn key, acc ->
      if Map.has_key?(source_map, key), do: Map.put(acc, key, source_map[key]), else: acc
    end)
  end
end
