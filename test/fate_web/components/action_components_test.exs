defmodule FateWeb.ActionComponentsTest do
  use ExUnit.Case, async: true

  alias FateWeb.ActionComponents

  @empty_state %Fate.Engine.State.DerivedState{
    entities: %{},
    scenes: []
  }

  describe "event_log_index_tooltip/2" do
    test "nil for short notes" do
      event = %{
        type: :note,
        detail: %{"text" => String.duplicate("a", 60)},
        description: nil
      }

      assert ActionComponents.event_log_index_tooltip(event, @empty_state) == nil
    end

    test "full text for long notes" do
      text = String.duplicate("word ", 20) |> String.trim()
      assert String.length(text) > 60

      event = %{type: :note, detail: %{"text" => text}, description: nil}

      assert ActionComponents.event_log_index_tooltip(event, @empty_state) == text
    end

    test "nil for empty note text" do
      event = %{type: :note, detail: %{}, description: nil}
      assert ActionComponents.event_log_index_tooltip(event, @empty_state) == nil
    end

    test "entity_modify lists present detail fields" do
      event = %{
        type: :entity_modify,
        detail: %{
          "name" => "River",
          "fate_points" => 3,
          "table_x" => 10,
          "table_y" => 20
        }
      }

      tip = ActionComponents.event_log_index_tooltip(event, @empty_state)
      assert tip =~ "Name: River"
      assert tip =~ "Fate points: 3"
      assert tip =~ "Table position: (10, 20)"
    end

    test "nil for entity_modify with no tooltip fields" do
      event = %{type: :entity_modify, detail: %{}}
      assert ActionComponents.event_log_index_tooltip(event, @empty_state) == nil
    end

    test "scene_modify shows non-empty fields" do
      event = %{
        type: :scene_modify,
        detail: %{
          "name" => "Warehouse",
          "description" => "  ",
          "gm_notes" => "Secret door"
        }
      }

      tip = ActionComponents.event_log_index_tooltip(event, @empty_state)
      assert tip =~ "Name: Warehouse"
      refute tip =~ "Description:"
      assert tip =~ "GM notes: Secret door"
    end

    test "stunt_add shows effect when present" do
      event = %{
        type: :stunt_add,
        detail: %{"name" => "Athletics+", "effect" => " +2 to leap"}
      }

      assert ActionComponents.event_log_index_tooltip(event, @empty_state) == "Effect:  +2 to leap"
    end

    test "nil for stunt_add without effect" do
      event = %{type: :stunt_add, detail: %{"name" => "Only name"}}
      assert ActionComponents.event_log_index_tooltip(event, @empty_state) == nil
    end

    test "nil for types without extra tooltip" do
      event = %{type: :roll_attack, detail: %{"skill" => "Fight"}, description: nil}
      assert ActionComponents.event_log_index_tooltip(event, @empty_state) == nil
    end
  end
end
