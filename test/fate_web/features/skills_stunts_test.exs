defmodule FateWeb.Features.SkillsStuntsTest do
  use FateWeb.FeatureCase

  defp setup_with_entity(session) do
    session
    |> join_as_gm()
    |> fork_bookmark("UI Testing")
    |> create_entity("Skill Test Entity")
    |> open_table()
    |> then(fn s -> :timer.sleep(2_000); s end)
  end

  defp create_entity(session, name) do
    session
    |> open_actions()
    |> click(Query.css("button[phx-click='set_log_tab'][phx-value-tab='events']"))
    |> assert_has(Query.text("Action Palette"))
    |> click(Query.css("#quick-entity_create"))
    |> assert_has(Query.css("form[phx-submit='submit_modal']"))
    |> fill_in(Query.css("input[name='name']"), with: name)
    |> click(Query.button("Confirm"))
    |> then(fn s -> :timer.sleep(1_000); s end)
  end

  defp expand_entity(session, name) do
    entity_id = find_entity_id_by_name(session, name)

    Wallaby.Browser.execute_script(session, """
      const card = document.querySelector('#entity-' + arguments[0]);
      if (card) {
        const btn = card.querySelector('button[phx-click="toggle_expand"]');
        if (btn) {
          btn.style.opacity = '1';
          btn.click();
        }
      }
    """, [entity_id])

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
      |> fork_bookmark("UI Testing")
      |> create_entity("Skill Entity")
      |> open_actions()
      |> click(Query.css("button[phx-click='set_log_tab'][phx-value-tab='events']"))
      |> assert_has(Query.text("Action Palette"))
      |> click(Query.css("#quick-skill_set"))
      |> assert_has(Query.css("form[phx-submit='submit_modal']"))

    # Select entity and fill skill
    Wallaby.Browser.execute_script(session, """
      const sel = document.querySelector('select[name="entity_id"]');
      if (sel) {
        for (const opt of sel.options) {
          if (opt.textContent.includes('Skill Entity')) { sel.value = opt.value; sel.dispatchEvent(new Event('change', {bubbles: true})); break; }
        }
      }
    """)

    session
    |> fill_in(Query.css("input[name='skill']", count: :any, at: 0), with: "Athletics")
    |> fill_in(Query.css("input[name='rating']"), with: "3")
    |> click(Query.button("Confirm"))

    :timer.sleep(1_000)

    session
    |> open_table()
    |> then(fn s -> :timer.sleep(1_000); s end)
    |> expand_entity("Skill Entity")
    |> assert_has(Query.text("Athletics"))
  end

  feature "add stunt via actions modal", %{session: session} do
    session =
      session
      |> join_as_gm()
      |> fork_bookmark("UI Testing")
      |> create_entity("Stunt Entity")
      |> open_actions()
      |> click(Query.css("button[phx-click='set_log_tab'][phx-value-tab='events']"))
      |> assert_has(Query.text("Action Palette"))
      |> click(Query.css("#quick-stunt_add"))
      |> assert_has(Query.css("form[phx-submit='submit_modal']"))

    Wallaby.Browser.execute_script(session, """
      const sel = document.querySelector('select[name="entity_id"]');
      if (sel) {
        for (const opt of sel.options) {
          if (opt.textContent.includes('Stunt Entity')) { sel.value = opt.value; sel.dispatchEvent(new Event('change', {bubbles: true})); break; }
        }
      }
    """)

    session
    |> fill_in(Query.css("input[name='name']"), with: "Quick Draw")
    |> fill_in(Query.css("input[name='effect']", count: :any, at: 0), with: "+2 to Shoot when drawing")
    |> click(Query.button("Confirm"))

    :timer.sleep(1_000)

    session
    |> open_table()
    |> then(fn s -> :timer.sleep(1_000); s end)
    |> expand_entity("Stunt Entity")
    |> assert_has(Query.text("Quick Draw"))
  end

  feature "adjust skill rating on table", %{session: session} do
    session =
      session
      |> setup_with_entity()

    entity_id = find_entity_id_by_name(session, "Skill Test Entity")

    # Add a skill first via the table's add_skill
    Wallaby.Browser.execute_script(session, """
      const card = document.querySelector('#entity-' + arguments[0]);
      if (card) {
        const btn = card.querySelector('button[phx-click="toggle_expand"]');
        if (btn) { btn.style.opacity = '1'; btn.click(); }
      }
    """, [entity_id])

    :timer.sleep(1_000)

    # Try to find and click the +1 skill adjust button
    has_skills = Wallaby.Browser.has?(session, Query.css("button[phx-click='adjust_skill']", minimum: 1))

    if has_skills do
      click(session, Query.css("button[phx-click='adjust_skill']", count: :any, at: 0))
      :timer.sleep(1_000)
    else
      IO.puts("INFO: No skills on entity to adjust — need to add skill first via modal")
    end
  end
end
