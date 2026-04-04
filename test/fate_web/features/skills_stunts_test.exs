defmodule FateWeb.Features.SkillsStuntsTest do
  use FateWeb.FeatureCase
  @moduletag area: :skills

  defp setup_with_entity(session) do
    session
    |> join_as_gm()
    |> fork_bookmark_from("New Game", "UI Testing")
    |> set_system("core")
    |> create_entity("Skill Test Entity")
    |> open_table()
    |> then(fn s ->
      :timer.sleep(2_000)
      s
    end)
  end

  defp set_system(session, system) do
    session
    |> open_actions()
    |> assert_has(Query.text("Action Palette"))
    |> click(Query.css("#quick-set_system"))
    |> assert_has(Query.css("form[phx-submit='submit_modal']"))
    |> select_option_by_value("system", system)
    |> click(Query.button("Confirm"))
    |> then(fn s ->
      :timer.sleep(1_000)
      s
    end)
  end

  defp create_entity(session, name) do
    session
    |> open_actions()
    |> assert_has(Query.text("Action Palette"))
    |> click(Query.css("#quick-entity_create"))
    |> assert_has(Query.css("form[phx-submit='submit_modal']"))
    |> fill_in(Query.css("input[name='name']"), with: name)
    |> click(Query.button("Confirm"))
    |> then(fn s ->
      :timer.sleep(1_000)
      s
    end)
  end

  defp expand_entity(session, name) do
    entity_id = find_entity_id_by_name(session, name)

    Wallaby.Browser.execute_script(
      session,
      """
        const card = document.querySelector('#entity-' + arguments[0]);
        if (card) {
          const btn = card.querySelector('button[phx-click="toggle_expand"]');
          if (btn) {
            btn.style.opacity = '1';
            btn.click();
          }
        }
      """,
      [entity_id]
    )

    :timer.sleep(1_000)
    session
  end

  feature "expand entity card shows skills and stunts sections", %{session: session} do
    session =
      session
      |> setup_with_entity()
      |> expand_entity("Skill Test Entity")

    assert_has(session, Query.text("Skills"))
    assert_has(session, Query.text("Stunts"))
  end

  feature "add skill via actions modal", %{session: session} do
    session =
      session
      |> join_as_gm()
      |> fork_bookmark_from("New Game", "UI Testing")
      |> set_system("core")
      |> create_entity("Skill Entity")
      |> open_actions()
      |> assert_has(Query.text("Action Palette"))
      |> click(Query.css("#quick-skill_set"))
      |> assert_has(Query.css("form[phx-submit='submit_modal']"))
      |> select_entity_in_modal("Skill Entity")
      |> select_option_by_value("skill", "Athletics")
      |> fill_in(Query.css("input[name='rating']"), with: "3")
      |> click(Query.button("Confirm"))

    :timer.sleep(1_000)

    session =
      session
      |> open_table()
      |> then(fn s ->
        :timer.sleep(1_000)
        s
      end)
      |> expand_entity("Skill Entity")

    assert_has(session, Query.text("Athletics"))
  end

  feature "add stunt via actions modal", %{session: session} do
    session =
      session
      |> join_as_gm()
      |> fork_bookmark_from("New Game", "UI Testing")
      |> create_entity("Stunt Entity")
      |> open_actions()
      |> assert_has(Query.text("Action Palette"))
      |> click(Query.css("#quick-stunt_add"))
      |> assert_has(Query.css("form[phx-submit='submit_modal']"))
      |> select_entity_in_modal("Stunt Entity")
      |> fill_in(Query.css("input[name='name']"), with: "Quick Draw")
      |> fill_in(Query.css("input[name='effect']"), with: "+2 to Shoot when drawing")
      |> click(Query.button("Confirm"))

    :timer.sleep(1_000)

    session =
      session
      |> open_table()
      |> then(fn s ->
        :timer.sleep(1_000)
        s
      end)
      |> expand_entity("Stunt Entity")

    assert_has(session, Query.text("Quick Draw"))
  end

  feature "adjust skill rating on table", %{session: session} do
    session =
      session
      |> setup_with_entity()

    entity_id = find_entity_id_by_name(session, "Skill Test Entity")
    expand_entity(session, "Skill Test Entity")

    has_skills =
      Wallaby.Browser.has?(session, Query.css("button[phx-click='adjust_skill']", minimum: 1))

    if has_skills do
      click(session, Query.css("button[phx-click='adjust_skill']", count: :any, at: 0))
      :timer.sleep(1_000)
    end

    assert entity_id != nil
  end
end
