defmodule Fate.Game.Demo do
  @moduledoc """
  Creates a demo campaign scenario (The Iron Carnival) for bootstrapping
  and demonstration purposes. All characters and setting are original.
  """

  alias Fate.Game

  def create do
    require Ash.Query

    case Ash.read(
           Fate.Game.Bookmark
           |> Ash.Query.filter(status: :active)
           |> Ash.Query.filter(is_nil(parent_bookmark_id))
         ) do
      {:ok, [root | _]} -> create_from_root(root)
      _ -> {:error, "No root bookmark found. Navigate to / first to bootstrap."}
    end
  end

  def create_from_root(root_bookmark) do
    kael_id = Ash.UUID.generate()
    mira_id = Ash.UUID.generate()
    thatch_id = Ash.UUID.generate()
    oathkeeper_id = Ash.UUID.generate()
    shield_id = Ash.UUID.generate()
    gadget_id = Ash.UUID.generate()
    maze_id = Ash.UUID.generate()

    with {:ok, player} <-
           Game.create_participant(%{name: "Ruthie", color: "#2563eb"}),
         {:ok, player2} <-
           Game.create_participant(%{name: "Lenny", color: "#16a34a"}),
         {:ok, player3} <-
           Game.create_participant(%{name: "Amanda", color: "#d946ef"}),
         {:ok, bmk_event} <-
           Game.append_event(%{
             parent_id: root_bookmark.head_event_id,
             type: :bookmark_create,
             description: "The Iron Carnival — Demo",
             detail: %{"name" => "The Iron Carnival — Demo"}
           }),
         {:ok, npc} <-
           Game.append_event(%{
             parent_id: bmk_event.id,
             type: :entity_create,
             description: "Create Vesper Nighthollow",
             detail: %{
               "entity_id" => Ash.UUID.generate(),
               "name" => "Vesper Nighthollow",
               "kind" => "npc",
               "fate_points" => 3,
               "color" => "#dc2626",
               "aspects" => [
                 %{
                   "description" => "Ringmaster of the Iron Carnival",
                   "role" => "high_concept"
                 },
                 %{"description" => "Everyone Has a Price", "role" => "trouble"}
               ],
               "skills" => %{
                 "Deceive" => 4,
                 "Rapport" => 3,
                 "Will" => 3,
                 "Resources" => 2,
                 "Provoke" => 2,
                 "Notice" => 1
               },
               "stunts" => [
                 %{
                   "name" => "Silver Tongue",
                   "effect" => "+2 to Deceive when making a deal or negotiating terms"
                 }
               ],
               "stress_tracks" => [
                 %{"label" => "physical", "boxes" => 2},
                 %{"label" => "mental", "boxes" => 3}
               ]
             }
           }),
         {:ok, pc} <-
           Game.append_event(%{
             parent_id: npc.id,
             type: :entity_create,
             description: "Create Kael Ashford",
             detail: %{
               "entity_id" => kael_id,
               "name" => "Kael Ashford",
               "kind" => "pc",
               "fate_points" => 3,
               "refresh" => 3,
               "color" => "#2563eb",
               "controller_id" => player.id,
               "aspects" => [
                 %{
                   "description" => "Disgraced Knight Seeking Redemption",
                   "role" => "high_concept"
                 },
                 %{"description" => "Can't Walk Away from Trouble", "role" => "trouble"},
                 %{"description" => "Old Friends in Low Places", "role" => "additional"}
               ],
               "skills" => %{
                 "Fight" => 4,
                 "Athletics" => 3,
                 "Will" => 3,
                 "Physique" => 2,
                 "Provoke" => 2,
                 "Notice" => 1,
                 "Empathy" => 1
               },
               "stunts" => [
                 %{
                   "name" => "Shield Wall",
                   "effect" => "+2 to defend with Fight when using a shield"
                 }
               ],
               "stress_tracks" => [
                 %{"label" => "physical", "boxes" => 3},
                 %{"label" => "mental", "boxes" => 3}
               ]
             }
           }),
         {:ok, scene} <-
           Game.append_event(%{
             parent_id: pc.id,
             type: :scene_start,
             description: "Behind the Big Top",
             detail: %{
               "scene_id" => Ash.UUID.generate(),
               "name" => "Behind the Big Top",
               "description" =>
                 "The carnival has set up on the old fairgrounds outside Thornwall. Behind the main tent, wagons and animal pens crowd together in the torchlight.",
               "zones" => [
                 %{"name" => "Backstage", "sort_order" => 0},
                 %{"name" => "Animal Pens", "sort_order" => 1},
                 %{"name" => "Ringmaster's Wagon", "sort_order" => 2}
               ],
               "aspects" => [
                 %{"description" => "Flickering Torchlight", "role" => "situation"},
                 %{"description" => "Crowded with Wagons and Props", "role" => "situation"},
                 %{"description" => "Distant Carnival Music", "role" => "situation"}
               ],
               "gm_notes" =>
                 "Vesper is in his wagon counting tonight's take. Grix patrols the animal pens. The stolen artifacts are hidden in a false floor under the lion cage."
             }
           }),
         {:ok, pc2} <-
           Game.append_event(%{
             parent_id: scene.id,
             type: :entity_create,
             description: "Create Mira Sandoval",
             detail: %{
               "entity_id" => mira_id,
               "name" => "Mira Sandoval",
               "kind" => "pc",
               "fate_points" => 3,
               "refresh" => 3,
               "color" => "#16a34a",
               "controller_id" => player2.id,
               "aspects" => [
                 %{
                   "description" => "Street-Smart Fence with a Heart of Gold",
                   "role" => "high_concept"
                 },
                 %{"description" => "My Brother's Keeper", "role" => "trouble"},
                 %{"description" => "I Know a Guy", "role" => "additional"}
               ],
               "skills" => %{
                 "Burglary" => 4,
                 "Stealth" => 3,
                 "Contacts" => 3,
                 "Deceive" => 2,
                 "Athletics" => 2,
                 "Notice" => 1,
                 "Rapport" => 1
               },
               "stunts" => [
                 %{
                   "name" => "Quick Fingers",
                   "effect" => "+2 to Burglary when picking pockets or sleight of hand"
                 }
               ],
               "stress_tracks" => [
                 %{"label" => "physical", "boxes" => 2},
                 %{"label" => "mental", "boxes" => 2}
               ]
             }
           }),
         {:ok, sword} <-
           Game.append_event(%{
             parent_id: pc2.id,
             type: :entity_create,
             description: "Create Kael's Sword",
             detail: %{
               "entity_id" => oathkeeper_id,
               "name" => "The Oathkeeper",
               "kind" => "item",
               "color" => "#2563eb",
               "controller_id" => player.id,
               "parent_entity_id" => kael_id,
               "aspects" => [
                 %{"description" => "Blade Sworn to Justice", "role" => "high_concept"}
               ],
               "stunts" => [
                 %{
                   "name" => "Righteous Strike",
                   "effect" =>
                     "Once per scene, +2 shifts on a successful Fight attack against a dishonourable foe"
                 }
               ]
             }
           }),
         {:ok, shield} <-
           Game.append_event(%{
             parent_id: sword.id,
             type: :entity_create,
             description: "Create Kael's Shield",
             detail: %{
               "entity_id" => shield_id,
               "name" => "Tower Shield",
               "kind" => "item",
               "color" => "#2563eb",
               "controller_id" => player.id,
               "parent_entity_id" => kael_id,
               "aspects" => [
                 %{"description" => "Scarred but Steadfast", "role" => "high_concept"}
               ]
             }
           }),
         {:ok, pc3} <-
           Game.append_event(%{
             parent_id: shield.id,
             type: :entity_create,
             description: "Create Professor Thatch",
             detail: %{
               "entity_id" => thatch_id,
               "name" => "Professor Elwin Thatch",
               "kind" => "pc",
               "fate_points" => 3,
               "refresh" => 2,
               "color" => "#d946ef",
               "controller_id" => player3.id,
               "aspects" => [
                 %{
                   "description" => "Eccentric Inventor and Amateur Sleuth",
                   "role" => "high_concept"
                 },
                 %{"description" => "Curiosity Over Caution", "role" => "trouble"},
                 %{
                   "description" => "Published in the Thornwall Gazette",
                   "role" => "additional"
                 },
                 %{"description" => "Always Carrying Something Useful", "role" => "additional"}
               ],
               "skills" => %{
                 "Lore" => 4,
                 "Investigate" => 3,
                 "Crafts" => 3,
                 "Notice" => 2,
                 "Empathy" => 2,
                 "Will" => 2,
                 "Rapport" => 1
               },
               "stunts" => [
                 %{
                   "name" => "Analytical Mind",
                   "effect" => "+2 to Investigate when examining a crime scene or puzzle"
                 },
                 %{
                   "name" => "Gadgeteer",
                   "effect" => "Once per session, declare you have a small useful device on hand"
                 }
               ],
               "stress_tracks" => [
                 %{"label" => "physical", "boxes" => 2},
                 %{"label" => "mental", "boxes" => 3}
               ]
             }
           }),
         {:ok, gadget} <-
           Game.append_event(%{
             parent_id: pc3.id,
             type: :entity_create,
             description: "Create Thatch's Gadget",
             detail: %{
               "entity_id" => gadget_id,
               "name" => "The Analyticator",
               "kind" => "item",
               "color" => "#d946ef",
               "controller_id" => player3.id,
               "parent_entity_id" => thatch_id,
               "aspects" => [
                 %{"description" => "Clockwork Detection Device", "role" => "high_concept"}
               ],
               "stunts" => [
                 %{
                   "name" => "Resonance Scan",
                   "effect" =>
                     "Once per scene, use Crafts instead of Notice to detect hidden objects"
                 }
               ]
             }
           }),
         {:ok, maze} <-
           Game.append_event(%{
             parent_id: gadget.id,
             type: :entity_create,
             description: "Create the Mirror Maze",
             detail: %{
               "entity_id" => maze_id,
               "name" => "The Haunted Mirror Maze",
               "kind" => "hazard",
               "color" => "#64748b",
               "aspects" => [
                 %{"description" => "Endless Reflections", "role" => "high_concept"},
                 %{"description" => "Whispers from the Glass", "role" => "trouble"}
               ],
               "skills" => %{
                 "Deceive" => 3,
                 "Provoke" => 4
               },
               "stress_tracks" => [
                 %{"label" => "structural", "boxes" => 4}
               ]
             }
           }),
         {:ok, grix} <-
           Game.append_event(%{
             parent_id: maze.id,
             type: :entity_create,
             description: "Create Grix",
             detail: %{
               "entity_id" => Ash.UUID.generate(),
               "name" => "Grix",
               "kind" => "npc",
               "fate_points" => 2,
               "color" => "#92400e",
               "aspects" => [
                 %{
                   "description" => "The Carnival's Silent Muscle",
                   "role" => "high_concept",
                   "hidden" => true
                 },
                 %{
                   "description" => "Follows Orders Without Question",
                   "role" => "trouble",
                   "hidden" => true
                 }
               ],
               "skills" => %{
                 "Fight" => 3,
                 "Physique" => 3,
                 "Athletics" => 2,
                 "Notice" => 1
               },
               "stress_tracks" => [
                 %{"label" => "physical", "boxes" => 3},
                 %{"label" => "mental", "boxes" => 2}
               ]
             }
           }),
         {:ok, bookmark} <-
           Game.create_bookmark(%{
             name: "The Iron Carnival — Demo",
             head_event_id: grix.id,
             parent_bookmark_id: root_bookmark.id
           }),
         {:ok, _bp} <-
           Game.create_bookmark_participant(%{
             bookmark_id: bookmark.id,
             participant_id: player.id,
             role: :player,
             seat_index: 0
           }),
         {:ok, _bp2} <-
           Game.create_bookmark_participant(%{
             bookmark_id: bookmark.id,
             participant_id: player2.id,
             role: :player,
             seat_index: 1
           }),
         {:ok, _bp3} <-
           Game.create_bookmark_participant(%{
             bookmark_id: bookmark.id,
             participant_id: player3.id,
             role: :player,
             seat_index: 2
           }) do
      {:ok, bookmark}
    end
  end
end
