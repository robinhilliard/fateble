defmodule FateWeb.ActionHelpersTest do
  use ExUnit.Case, async: true

  alias FateWeb.ActionHelpers

  describe "merge_edit_detail/5" do
    test "entity_edit leaves detail unchanged when params match baseline" do
      original = %{"entity_id" => "e1", "name" => "Pat"}

      baseline = %{
        "event_id" => "evt",
        "entity_id" => "e1",
        "name" => "Pat",
        "kind" => "pc",
        "controller_id" => "",
        "fate_points" => "3",
        "refresh" => "3"
      }

      params = %{
        "event_id" => "evt",
        "entity_id" => "e1",
        "name" => "Pat",
        "kind" => "pc",
        "controller_id" => "",
        "fate_points" => "3",
        "refresh" => "3"
      }

      merged =
        ActionHelpers.merge_edit_detail("entity_edit", original, baseline, params, [])

      assert merged == original
    end

    test "entity_edit adds only changed keys to original patch" do
      original = %{"entity_id" => "e1", "name" => "Pat"}

      baseline =
        Map.merge(original, %{
          "event_id" => "evt",
          "kind" => "pc",
          "controller_id" => "",
          "fate_points" => "",
          "refresh" => ""
        })

      params = %{
        "event_id" => "evt",
        "entity_id" => "e1",
        "name" => "Pat 2",
        "kind" => "pc",
        "controller_id" => "",
        "fate_points" => "",
        "refresh" => ""
      }

      merged =
        ActionHelpers.merge_edit_detail("entity_edit", original, baseline, params, [])

      assert merged["name"] == "Pat 2"
      assert merged["entity_id"] == "e1"
      refute Map.has_key?(merged, "kind")
    end

    test "entity_create updates aspects when high concept or additional lines change" do
      original = %{
        "entity_id" => "e1",
        "name" => "Sam",
        "aspects" => [
          %{"role" => "high_concept", "description" => "Old"},
          %{"role" => "trouble", "description" => "Bad"}
        ]
      }

      baseline = %{
        "event_id" => "evt",
        "entity_id" => "e1",
        "name" => "Sam",
        "kind" => "pc",
        "high_concept" => "Old",
        "trouble" => "Bad",
        "additional_aspects" => ""
      }

      params =
        Map.merge(baseline, %{
          "high_concept" => "New HC",
          "additional_aspects" => "Just text\nconsequence|Broken arm"
        })

      merged =
        ActionHelpers.merge_edit_detail("entity_create", original, baseline, params, [])

      assert [%{"role" => "high_concept", "description" => "New HC"}, tr, add1, add2] =
               merged["aspects"]

      assert tr == %{"role" => "trouble", "description" => "Bad"}
      assert add1 == %{"role" => "additional", "description" => "Just text"}
      assert add2 == %{"role" => "consequence", "description" => "Broken arm"}
    end
  end

  describe "entity_create_aspects_from_form_params/1" do
    test "builds ordered list: high concept, trouble, then additional lines" do
      params = %{
        "high_concept" => "  Hero  ",
        "trouble" => "Cursed",
        "additional_aspects" => "Plain\nsituation|On fire"
      }

      assert ActionHelpers.entity_create_aspects_from_form_params(params) == [
               %{"role" => "high_concept", "description" => "Hero"},
               %{"role" => "trouble", "description" => "Cursed"},
               %{"role" => "additional", "description" => "Plain"},
               %{"role" => "situation", "description" => "On fire"}
             ]
    end

    test "legacy single aspects textarea still parses when split fields absent" do
      params = %{"aspects" => "trouble|Oops\nExtra"}

      assert ActionHelpers.entity_create_aspects_from_form_params(params) == [
               %{"role" => "trouble", "description" => "Oops"},
               %{"role" => "additional", "description" => "Extra"}
             ]
    end
  end
end
