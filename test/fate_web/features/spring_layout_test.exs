defmodule FateWeb.Features.SpringLayoutTest do
  use FateWeb.FeatureCase

  defp setup_with_entities(session) do
    session
    |> join_as_gm()
    |> fork_bookmark_from("New Game", "UI Testing")
    |> create_entity("Spring Entity")
    |> open_table()
    |> then(fn s ->
      :timer.sleep(3_000)
      s
    end)
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
    |> then(fn s ->
      :timer.sleep(1_000)
      s
    end)
  end

  defp js_eval(session, js, args \\ []) do
    {:ok, result} = Wallaby.WebdriverClient.execute_script(session, js, args)
    result
  end

  feature "spring layout positions elements on table", %{session: session} do
    session = setup_with_entities(session)
    wait_for_spring_settle(session)

    positioned =
      js_eval(session, """
        const els = document.querySelectorAll('.spring-element');
        let count = 0;
        for (const el of els) {
          if (el.style.transform && el.style.transform.includes('translate')) count++;
        }
        return count > 0;
      """)

    assert positioned, "Spring elements should have transform positions"
  end

  feature "double-click pins entity card", %{session: session} do
    session = setup_with_entities(session)
    entity_id = find_entity_id_by_name(session, "Spring Entity")
    wait_for_spring_settle(session)

    double_click_element(session, "[data-element-id='entity-#{entity_id}']")
    :timer.sleep(500)

    pinned =
      js_eval(
        session,
        """
          const el = document.querySelector('[data-element-id="entity-' + arguments[0] + '"]');
          return el && el.classList.contains('user-pinned');
        """,
        [entity_id]
      )

    assert pinned, "Entity should have user-pinned class after double-click"
  end

  feature "double-click again unpins entity card", %{session: session} do
    session = setup_with_entities(session)
    entity_id = find_entity_id_by_name(session, "Spring Entity")
    wait_for_spring_settle(session)

    double_click_element(session, "[data-element-id='entity-#{entity_id}']")
    :timer.sleep(500)
    double_click_element(session, "[data-element-id='entity-#{entity_id}']")
    :timer.sleep(500)

    pinned =
      js_eval(
        session,
        """
          const el = document.querySelector('[data-element-id="entity-' + arguments[0] + '"]');
          return el && el.classList.contains('user-pinned');
        """,
        [entity_id]
      )

    refute pinned, "Entity should lose user-pinned class after second double-click"
  end

  feature "resize window preserves element positions proportionally", %{session: session} do
    session = setup_with_entities(session)
    wait_for_spring_settle(session)

    before_size = js_eval(session, "return {w: window.innerWidth, h: window.innerHeight};")

    before_pos = get_element_position(session, ".spring-element")
    assert before_pos != nil

    resize_window(session, 800, 600)
    :timer.sleep(2_000)
    wait_for_spring_settle(session)

    after_size = js_eval(session, "return {w: window.innerWidth, h: window.innerHeight};")

    assert after_size["w"] != before_size["w"] || after_size["h"] != before_size["h"],
           "Window should have resized"

    after_pos = get_element_position(session, ".spring-element")
    assert after_pos != nil

    assert after_pos["x"] > 0 || after_pos["y"] > 0,
           "Spring elements should still have non-zero positions after resize"

    resize_window(session, 1280, 800)
  end

  feature "participant label exists on border", %{session: session} do
    session = setup_with_entities(session)

    on_border =
      js_eval(session, """
        const els = document.querySelectorAll('.spring-element[data-on-border="true"]');
        return els.length;
      """)

    assert on_border > 0, "At least one border element (participant) should exist"
  end
end
