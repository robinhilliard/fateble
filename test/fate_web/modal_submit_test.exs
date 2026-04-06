defmodule FateWeb.ModalSubmitTest do
  use ExUnit.Case, async: true

  alias FateWeb.ModalSubmit

  test "aspect_create_attrs panel builds detail with hidden flag" do
    params = %{
      "target_ref" => "entity:e1",
      "description" => "  On fire  ",
      "role" => "boost",
      "hidden" => "true"
    }

    assert {:ok, %{type: :aspect_create, detail: detail}} =
             ModalSubmit.aspect_create_attrs(params, :panel)

    assert detail["target_id"] == "e1"
    assert detail["target_type"] == "entity"
    assert detail["description"] == "On fire"
    assert detail["role"] == "boost"
    assert detail["hidden"] == true
  end

  test "aspect_create_attrs table_scene forces situation role" do
    params = %{"target_ref" => "scene:s1", "description" => "Smoke"}

    assert {:ok, %{detail: detail}} =
             ModalSubmit.aspect_create_attrs(params, {:table_scene, false})

    assert detail["role"] == "situation"
    refute Map.has_key?(detail, "hidden")
  end

  test "aspect_create_attrs table_entity uses fixed id" do
    params = %{"description" => "Bleeding", "role" => "consequence"}

    assert {:ok, %{target_id: "ent42", detail: detail}} =
             ModalSubmit.aspect_create_attrs(params, {:table_entity, "ent42"})

    assert detail["target_type"] == "entity"
    assert detail["description"] == "Bleeding"
    assert detail["role"] == "consequence"
  end

  test "aspect_create_attrs rejects empty description" do
    assert :error == ModalSubmit.aspect_create_attrs(%{"description" => "  "}, :panel)
  end

  test "note_attrs includes target when target_ref set" do
    params = %{
      "text" => "  Hello  ",
      "target_ref" => "entity:e99"
    }

    assert {:ok, %{type: :note, target_id: "e99", detail: d}} = ModalSubmit.note_attrs(params)
    assert d["text"] == "Hello"
    assert d["target_type"] == "entity"
  end

  test "note_attrs rejects empty text" do
    assert :error == ModalSubmit.note_attrs(%{"text" => "  "})
  end

  test "template_scene_create_attrs uses given scene id" do
    params = %{
      "name" => "Dock",
      "scene_description" => "Fog",
      "gm_notes" => "Secret"
    }

    assert %{type: :template_scene_create, detail: d} =
             ModalSubmit.template_scene_create_attrs(params, "scene-uuid-1")

    assert d["scene_id"] == "scene-uuid-1"
    assert d["name"] == "Dock"
    assert d["description"] == "Fog"
    assert d["gm_notes"] == "Secret"
  end

  test "entity_modify_attrs sets color from participant" do
    participants = [
      %{participant_id: "p1", participant: %{color: "#c0ffee", name: "Sam"}}
    ]

    params = %{
      "entity_id" => "e1",
      "name" => "Renamed",
      "kind" => "pc",
      "controller_id" => "p1",
      "fate_points" => "3",
      "refresh" => "2"
    }

    assert %{type: :entity_modify, detail: d} =
             ModalSubmit.entity_modify_attrs(params, participants, "Renamed")

    assert d["color"] == "#c0ffee"
    assert d["fate_points"] == 3
    assert d["refresh"] == 2
  end

  test "stunt_add_attrs accepts panel name/effect or table stunt_name/stunt_effect" do
    p1 = %{
      "entity_id" => "e1",
      "name" => "A",
      "effect" => "B",
      "stunt_id" => "fixed-id"
    }

    assert %{detail: d1} = ModalSubmit.stunt_add_attrs(p1)
    assert d1["name"] == "A"
    assert d1["effect"] == "B"
    assert d1["stunt_id"] == "fixed-id"

    p2 = %{"stunt_name" => "Slash", "stunt_effect" => "+2 Fight"}
    assert %{target_id: "e9", detail: d2} = ModalSubmit.stunt_add_attrs(p2, "e9")
    assert d2["name"] == "Slash"
    assert d2["effect"] == "+2 Fight"
  end

  test "template_scene_modify_attrs patches scene fields" do
    params = %{
      "scene_id" => "s1",
      "name" => "New",
      "scene_description" => "Desc",
      "gm_notes" => "N"
    }

    assert %{type: :template_scene_modify, detail: d} =
             ModalSubmit.template_scene_modify_attrs(params)

    assert d["scene_id"] == "s1"
    assert d["name"] == "New"
    assert d["description"] == "Desc"
    assert d["gm_notes"] == "N"
  end

  test "scene_end_attrs is ok for active scene only" do
    assert :error == ModalSubmit.scene_end_attrs(nil)

    assert {:ok, %{type: :active_scene_end, detail: %{"scene_id" => "s9"}}} =
             ModalSubmit.scene_end_attrs(%{id: "s9", name: "Alley"})
  end

  test "entity_create_attrs sets color and optional aspects" do
    participants = [
      %{participant_id: "p1", participant: %{color: "#abc", name: "Sam"}}
    ]

    params = %{
      "name" => "Hero",
      "kind" => "pc",
      "controller_id" => "p1",
      "high_concept" => "Brave",
      "trouble" => "",
      "additional_aspects" => ""
    }

    assert %{type: :entity_create, detail: d} =
             ModalSubmit.entity_create_attrs(params, participants)

    assert d["color"] == "#abc"
    assert [%{"role" => "high_concept", "description" => "Brave"}] = d["aspects"]
  end

  test "skill_set_attrs parses rating" do
    params = %{"entity_id" => "e1", "skill" => "Fight", "rating" => "3"}
    assert %{detail: d} = ModalSubmit.skill_set_attrs(params)
    assert d["rating"] == 3
  end

  test "aspect_compel_attrs includes accepted flag" do
    params = %{
      "target_id" => "e1",
      "aspect_id" => "a1",
      "description" => "Trip",
      "actor_id" => "",
      "accepted" => "false"
    }

    assert %{detail: d} = ModalSubmit.aspect_compel_attrs(params, "Pat")
    assert d["accepted"] == false
  end

  test "template_zone_create_attrs generates zone id and hidden" do
    params = %{"name" => "Roof"}

    assert %{type: :template_zone_create, detail: d} =
             ModalSubmit.template_zone_create_attrs("scene-1", params)

    assert d["scene_id"] == "scene-1"
    assert d["name"] == "Roof"
    assert d["hidden"] == true
    assert is_binary(d["zone_id"])
  end

  test "fate_point_spend_attrs optional description" do
    p = %{"entity_id" => "e1"}

    assert %{description: "Spend fate point"} = ModalSubmit.fate_point_spend_attrs(p)

    assert %{description: "Spend FP to invoke: tag"} =
             ModalSubmit.fate_point_spend_attrs(p, description: "Spend FP to invoke: tag")
  end

  test "ring_invoke_aspect_events orders spend then invoke when not free" do
    assert [spend, invoke] = ModalSubmit.ring_invoke_aspect_events("e1", "Dark", false)
    assert spend.type == :fate_point_spend
    assert spend.description == "Spend FP to invoke: Dark"
    assert invoke.type == :invoke
    assert invoke.description == "Invoke: Dark (FP)"
    assert invoke.detail["free"] == false
  end

  test "ring_invoke_aspect_events skips spend when free" do
    assert [invoke] = ModalSubmit.ring_invoke_aspect_events("e1", "Lit", true)
    assert invoke.type == :invoke
    assert invoke.description == "Invoke: Lit (free)"
    assert invoke.detail["free"] == true
  end

  test "ring_compel_accepted_events builds compel and earn pair" do
    assert [c, e] = ModalSubmit.ring_compel_accepted_events("e1", "a9", "Slip")
    assert c.type == :aspect_compel
    assert c.description == "Compel: Slip"
    assert c.detail["accepted"] == true
    assert e.type == :fate_point_earn
    assert e.description == "Earn FP from compel: Slip"
  end

  test "table ring entity_remove_attrs keeps name in detail" do
    assert %{type: :entity_remove, detail: d} = ModalSubmit.entity_remove_attrs("e1", "Bob")
    assert d["entity_id"] == "e1"
    assert d["name"] == "Bob"
  end
end
