defmodule FateWeb.ModalComponents do
  @moduledoc """
  Shared modal shell (overlay, card, title) for table and player-panel dialogs.
  """

  use FateWeb, :html

  attr :variant, :atom,
    required: true,
    values: [:table, :panel],
    doc: "`:table` uses `z-[300]` and optional table close event defaults; `:panel` uses `z-50`."

  attr :close_event, :string,
    default: nil,
    doc: "Passed to cancel button and click-away; defaults from `variant` when nil."

  attr :escape_close, :boolean, default: true
  attr :inner_click_away, :boolean, default: false

  attr :inner_extra_class, :any,
    default: nil,
    doc: "Extra classes for the inner card (e.g. max height / scroll)."

  attr :overlay_extra_class, :any, default: nil

  slot :title, required: true
  slot :inner_block, required: true

  def modal_frame(assigns) do
    assigns =
      assigns
      |> assign_new(:close_event, fn ->
        case assigns.variant do
          :table -> "close_table_modal"
          :panel -> "close_modal"
        end
      end)

    z = if assigns.variant == :table, do: "z-[300]", else: "z-50"

    title_class =
      if assigns.variant == :table,
        do: "text-amber-100",
        else: nil

    assigns =
      assigns
      |> assign(:z_class, z)
      |> assign(:title_class, title_class)

    ~H"""
    <div
      class={[
        "fixed inset-0 flex items-center justify-center bg-black/60",
        @z_class,
        @overlay_extra_class
      ]}
      phx-window-keydown={if(@escape_close, do: @close_event)}
      phx-key={if(@escape_close, do: "escape")}
    >
      <div
        class={[
          "bg-amber-950 border border-amber-700/40 rounded-xl p-6 w-96 shadow-2xl",
          @inner_extra_class
        ]}
        phx-click-away={if(@inner_click_away, do: @close_event)}
      >
        <h3
          class={["text-lg font-bold mb-4", @title_class]}
          style="font-family: 'Permanent Marker', cursive;"
        >
          {render_slot(@title)}
        </h3>
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  attr :primary_label, :string, required: true
  attr :cancel_label, :string, default: "Cancel"
  attr :close_event, :string, required: true

  def modal_frame_actions(assigns) do
    ~H"""
    <div class="flex gap-2 pt-2">
      <button
        type="submit"
        class="flex-1 py-2 bg-green-800/60 border border-green-600/30 rounded-lg hover:bg-green-700/60 text-green-200 font-bold text-sm"
      >
        {@primary_label}
      </button>
      <button
        type="button"
        phx-click={@close_event}
        class="flex-1 py-2 bg-red-900/40 border border-red-700/30 rounded-lg hover:bg-red-800/40 text-red-200 text-sm"
      >
        {@cancel_label}
      </button>
    </div>
    """
  end
end
