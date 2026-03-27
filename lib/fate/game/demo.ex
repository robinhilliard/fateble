defmodule Fate.Game.Demo do
  @moduledoc """
  Creates a demo Fate campaign scenario (Sindral Reach) for bootstrapping
  and demonstration purposes.
  """

  alias Fate.Game.{Event, Bookmark, BookmarkParticipant, Participant}

  def create do
    require Ash.Query

    case Ash.read(
           Bookmark
           |> Ash.Query.filter(status: :active)
           |> Ash.Query.filter(is_nil(parent_bookmark_id))
         ) do
      {:ok, [root | _]} -> create_from_root(root)
      _ -> {:error, "No root bookmark found. Navigate to / first to bootstrap."}
    end
  end

  def create_from_root(root_bookmark) do
    cynere_id = Ash.UUID.generate()
    landon_id = Ash.UUID.generate()
    zird_id = Ash.UUID.generate()
    sword_id = Ash.UUID.generate()
    shield_id = Ash.UUID.generate()
    staff_id = Ash.UUID.generate()
    storm_id = Ash.UUID.generate()

    with {:ok, player} <-
           Ash.create(Participant, %{name: "Ruthie", color: "#2563eb"}, action: :create),
         {:ok, player2} <-
           Ash.create(Participant, %{name: "Lenny", color: "#16a34a"}, action: :create),
         {:ok, player3} <-
           Ash.create(Participant, %{name: "Amanda", color: "#d946ef"}, action: :create),
         {:ok, bmk_event} <-
           Ash.create(
             Event,
             %{
               parent_id: root_bookmark.head_event_id,
               type: :bookmark_create,
               description: "Sindral Reach — Demo",
               detail: %{"name" => "Sindral Reach — Demo"}
             },
             action: :append
           ),
         {:ok, npc} <-
           Ash.create(
             Event,
             %{
               parent_id: bmk_event.id,
               type: :entity_create,
               description: "Create Barathar",
               detail: %{
                 "entity_id" => Ash.UUID.generate(),
                 "name" => "Barathar",
                 "kind" => "npc",
                 "fate_points" => 3,
                 "color" => "#dc2626",
                 "aspects" => [
                   %{
                     "description" => "Smuggler Queen of the Sindral Reach",
                     "role" => "high_concept"
                   },
                   %{"description" => "Trusted by No One", "role" => "trouble"}
                 ],
                 "skills" => %{
                   "Deceive" => 4,
                   "Contacts" => 3,
                   "Resources" => 3,
                   "Will" => 2,
                   "Fight" => 2,
                   "Notice" => 1
                 },
                 "stunts" => [
                   %{
                     "name" => "Network of Informants",
                     "effect" => "+2 to Contacts when gathering information in port cities"
                   }
                 ],
                 "stress_tracks" => [
                   %{"label" => "physical", "boxes" => 2},
                   %{"label" => "mental", "boxes" => 3}
                 ]
               }
             },
             action: :append
           ),
         {:ok, pc} <-
           Ash.create(
             Event,
             %{
               parent_id: npc.id,
               type: :entity_create,
               description: "Create Cynere",
               detail: %{
                 "entity_id" => cynere_id,
                 "name" => "Cynere",
                 "kind" => "pc",
                 "fate_points" => 3,
                 "refresh" => 3,
                 "color" => "#2563eb",
                 "controller_id" => player.id,
                 "aspects" => [
                   %{"description" => "Infamous Girl with Sword", "role" => "high_concept"},
                   %{"description" => "Tempted by Shiny Things", "role" => "trouble"},
                   %{"description" => "Rivals in the Underworld", "role" => "additional"}
                 ],
                 "skills" => %{
                   "Fight" => 4,
                   "Athletics" => 3,
                   "Burglary" => 3,
                   "Provoke" => 2,
                   "Stealth" => 2,
                   "Notice" => 1,
                   "Physique" => 1
                 },
                 "stunts" => [
                   %{
                     "name" => "Master Swordswoman",
                     "effect" => "+2 to Fight when dueling one-on-one"
                   }
                 ],
                 "stress_tracks" => [
                   %{"label" => "physical", "boxes" => 3},
                   %{"label" => "mental", "boxes" => 2}
                 ]
               }
             },
             action: :append
           ),
         {:ok, scene} <-
           Ash.create(
             Event,
             %{
               parent_id: pc.id,
               type: :scene_start,
               description: "Dockside Warehouse",
               detail: %{
                 "scene_id" => Ash.UUID.generate(),
                 "name" => "Dockside Warehouse",
                 "description" =>
                   "A run-down warehouse at the edge of the docks. Crates everywhere. The loading door is open to the water.",
                 "zones" => [
                   %{"name" => "Main Floor", "sort_order" => 0},
                   %{"name" => "Upper Catwalk", "sort_order" => 1},
                   %{"name" => "Loading Dock", "sort_order" => 2}
                 ],
                 "aspects" => [
                   %{"description" => "Heavy Crates Everywhere", "role" => "situation"},
                   %{"description" => "Open to the Water", "role" => "situation"},
                   %{"description" => "Poorly Lit", "role" => "situation"}
                 ],
                 "gm_notes" =>
                   "Barathar waits on the upper catwalk with Og. The smuggled goods are in crates near the loading dock. If the PCs make noise, 4 thugs emerge from the main floor crates."
               }
             },
             action: :append
           ),
         {:ok, pc2} <-
           Ash.create(
             Event,
             %{
               parent_id: scene.id,
               type: :entity_create,
               description: "Create Landon",
               detail: %{
                 "entity_id" => landon_id,
                 "name" => "Landon",
                 "kind" => "pc",
                 "fate_points" => 3,
                 "refresh" => 3,
                 "color" => "#16a34a",
                 "controller_id" => player2.id,
                 "aspects" => [
                   %{"description" => "An Honest-to-Gods Swordsman", "role" => "high_concept"},
                   %{"description" => "I Owe Old Finn Everything", "role" => "trouble"},
                   %{"description" => "Muscle for Hire", "role" => "additional"}
                 ],
                 "skills" => %{
                   "Fight" => 4,
                   "Physique" => 3,
                   "Athletics" => 3,
                   "Will" => 2,
                   "Provoke" => 2,
                   "Notice" => 1,
                   "Contacts" => 1
                 },
                 "stunts" => [
                   %{
                     "name" => "Heavy Hitter",
                     "effect" => "+2 to Fight when using a two-handed weapon"
                   }
                 ],
                 "stress_tracks" => [
                   %{"label" => "physical", "boxes" => 4},
                   %{"label" => "mental", "boxes" => 2}
                 ]
               }
             },
             action: :append
           ),
         {:ok, sword} <-
           Ash.create(
             Event,
             %{
               parent_id: pc2.id,
               type: :entity_create,
               description: "Create Landon's Greatsword",
               detail: %{
                 "entity_id" => sword_id,
                 "name" => "Heartsplitter",
                 "kind" => "item",
                 "color" => "#16a34a",
                 "controller_id" => player2.id,
                 "parent_entity_id" => landon_id,
                 "aspects" => [
                   %{"description" => "Ancient Blade of the North", "role" => "high_concept"}
                 ],
                 "stunts" => [
                   %{
                     "name" => "Rending Strike",
                     "effect" => "Once per scene, add +2 shifts to a successful Fight attack"
                   }
                 ]
               }
             },
             action: :append
           ),
         {:ok, shield} <-
           Ash.create(
             Event,
             %{
               parent_id: sword.id,
               type: :entity_create,
               description: "Create Landon's Shield",
               detail: %{
                 "entity_id" => shield_id,
                 "name" => "Battered Kite Shield",
                 "kind" => "item",
                 "color" => "#16a34a",
                 "controller_id" => player2.id,
                 "parent_entity_id" => landon_id,
                 "aspects" => [
                   %{"description" => "Dented but Dependable", "role" => "high_concept"}
                 ]
               }
             },
             action: :append
           ),
         {:ok, pc3} <-
           Ash.create(
             Event,
             %{
               parent_id: shield.id,
               type: :entity_create,
               description: "Create Zird the Arcane",
               detail: %{
                 "entity_id" => zird_id,
                 "name" => "Zird the Arcane",
                 "kind" => "pc",
                 "fate_points" => 3,
                 "refresh" => 2,
                 "color" => "#d946ef",
                 "controller_id" => player3.id,
                 "aspects" => [
                   %{"description" => "Wizard of the Collegia Arcana", "role" => "high_concept"},
                   %{"description" => "Rivals in the Collegia", "role" => "trouble"},
                   %{
                     "description" => "If I Haven't Been There I've Read About It",
                     "role" => "additional"
                   },
                   %{"description" => "Not the Face!", "role" => "additional"}
                 ],
                 "skills" => %{
                   "Lore" => 4,
                   "Will" => 3,
                   "Investigate" => 3,
                   "Crafts" => 2,
                   "Empathy" => 2,
                   "Notice" => 2,
                   "Rapport" => 1
                 },
                 "stunts" => [
                   %{
                     "name" => "Arcane Shield",
                     "effect" =>
                       "Use Lore to defend against physical attacks when you can invoke a magical ward"
                   },
                   %{
                     "name" => "Scholar's Eye",
                     "effect" => "+2 to Investigate when examining magical artifacts"
                   }
                 ],
                 "stress_tracks" => [
                   %{"label" => "physical", "boxes" => 2},
                   %{"label" => "mental", "boxes" => 4}
                 ]
               }
             },
             action: :append
           ),
         {:ok, staff} <-
           Ash.create(
             Event,
             %{
               parent_id: pc3.id,
               type: :entity_create,
               description: "Create Zird's Staff",
               detail: %{
                 "entity_id" => staff_id,
                 "name" => "Staff of the Collegia",
                 "kind" => "item",
                 "color" => "#d946ef",
                 "controller_id" => player3.id,
                 "parent_entity_id" => zird_id,
                 "aspects" => [
                   %{"description" => "Focus of Arcane Power", "role" => "high_concept"}
                 ],
                 "stunts" => [
                   %{
                     "name" => "Channelled Blast",
                     "effect" => "Once per scene, use Lore instead of Shoot for a ranged attack"
                   }
                 ]
               }
             },
             action: :append
           ),
         {:ok, storm} <-
           Ash.create(
             Event,
             %{
               parent_id: staff.id,
               type: :entity_create,
               description: "Create the Storm",
               detail: %{
                 "entity_id" => storm_id,
                 "name" => "The Howling Gale",
                 "kind" => "hazard",
                 "color" => "#64748b",
                 "aspects" => [
                   %{"description" => "Relentless Fury of the Sea", "role" => "high_concept"},
                   %{"description" => "The Eye Passes Over", "role" => "trouble"}
                 ],
                 "skills" => %{
                   "Attack" => 3,
                   "Overcome" => 4
                 },
                 "stress_tracks" => [
                   %{"label" => "intensity", "boxes" => 4}
                 ]
               }
             },
             action: :append
           ),
         {:ok, og} <-
           Ash.create(
             Event,
             %{
               parent_id: storm.id,
               type: :entity_create,
               description: "Create Og",
               detail: %{
                 "entity_id" => Ash.UUID.generate(),
                 "name" => "Og the Strong",
                 "kind" => "npc",
                 "fate_points" => 2,
                 "color" => "#92400e",
                 "aspects" => [
                   %{
                     "description" => "Barathar's Loyal Enforcer",
                     "role" => "high_concept",
                     "hidden" => true
                   },
                   %{
                     "description" => "Dumb as a Bag of Hammers",
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
             },
             action: :append
           ),
         {:ok, bookmark} <-
           Ash.create(
             Bookmark,
             %{
               name: "Sindral Reach — Demo",
               head_event_id: og.id,
               parent_bookmark_id: root_bookmark.id
             },
             action: :create
           ),
         {:ok, _bp} <-
           Ash.create(
             BookmarkParticipant,
             %{
               bookmark_id: bookmark.id,
               participant_id: player.id,
               role: :player,
               seat_index: 0
             },
             action: :create
           ),
         {:ok, _bp2} <-
           Ash.create(
             BookmarkParticipant,
             %{
               bookmark_id: bookmark.id,
               participant_id: player2.id,
               role: :player,
               seat_index: 1
             },
             action: :create
           ),
         {:ok, _bp3} <-
           Ash.create(
             BookmarkParticipant,
             %{
               bookmark_id: bookmark.id,
               participant_id: player3.id,
               role: :player,
               seat_index: 2
             },
             action: :create
           ) do
      {:ok, bookmark}
    end
  end
end
