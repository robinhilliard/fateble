// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/fate"
import topbar from "../vendor/topbar"

import { SpringLayout } from "./spring_layout"
import { makeTouchDraggable, registerDropTarget, unregisterDropTarget } from "./touch_drag"
import { MentionTypeahead } from "./mention_typeahead"
import "tributejs/dist/tribute.css"

const DraggableEntity = {
  mounted() {
    this.el.addEventListener("dragstart", (e) => {
      e.dataTransfer.setData("entity-id", this.el.dataset.entityId)
      e.dataTransfer.setData("entity-name", this.el.dataset.entityName)
      e.dataTransfer.effectAllowed = "link"
      this.el.style.opacity = "0.5"
    })
    this.el.addEventListener("dragend", (e) => {
      this.el.style.opacity = ""
    })

    this._cleanupTouch = makeTouchDraggable(this.el, {
      getData: () => ({
        "entity-id": this.el.dataset.entityId,
        "entity-name": this.el.dataset.entityName,
      }),
      createGhost: (data) => {
        const ghost = document.createElement("div")
        ghost.className = "drag-ghost"
        ghost.textContent = data["entity-name"]
        ghost.style.cssText =
          "padding:4px 12px;background:#374151;color:#fff;border-radius:6px;font-size:13px;white-space:nowrap;opacity:0.9;"
        return ghost
      },
      onDragStart: () => {
        this.el.style.opacity = "0.5"
      },
      onDragEnd: () => {
        this.el.style.opacity = ""
      },
    })
  },
  destroyed() {
    if (this._cleanupTouch) this._cleanupTouch()
  },
}

const DropTarget = {
  mounted() {
    this._onDragOver = (e) => {
      if (e.dataTransfer && e.dataTransfer.types.includes("entity-id")) {
        e.preventDefault()
        e.dataTransfer.dropEffect = "link"
        this.el.classList.add("drop-hover")
      }
    }
    this._onDragLeave = () => {
      this.el.classList.remove("drop-hover")
    }
    this._onDrop = (e) => {
      this.el.classList.remove("drop-hover")
      const entityId = e.dataTransfer && e.dataTransfer.getData("entity-id")
      if (entityId) {
        e.preventDefault()
        e.stopPropagation()
        this.pushEvent("entity_dropped", {
          entity_id: entityId,
          action_type: this.el.dataset.actionType,
          action_category: this.el.dataset.actionCategory,
        })
      }
    }
    this.el.addEventListener("dragover", this._onDragOver)
    this.el.addEventListener("dragleave", this._onDragLeave)
    this.el.addEventListener("drop", this._onDrop)

    registerDropTarget(this.el, {
      accepts: (data) => !!data["entity-id"],
      onDrop: (data) => {
        this.pushEvent("entity_dropped", {
          entity_id: data["entity-id"],
          action_type: this.el.dataset.actionType,
          action_category: this.el.dataset.actionCategory,
        })
      },
      onHover: (el) => el.classList.add("drop-hover"),
      onLeave: (el) => el.classList.remove("drop-hover"),
    })
  },
  destroyed() {
    this.el.removeEventListener("dragover", this._onDragOver)
    this.el.removeEventListener("dragleave", this._onDragLeave)
    this.el.removeEventListener("drop", this._onDrop)
    unregisterDropTarget(this.el)
  },
}

const DraggableToken = {
  mounted() {
    this.el.addEventListener("dragstart", (e) => {
      e.stopPropagation()
      const name = this.el.dataset.entityName
      const color = this.el.dataset.entityColor
      const entityId = this.el.dataset.entityId

      e.dataTransfer.setData("entity-id", entityId)
      e.dataTransfer.setData("entity-name", name)
      if (this.el.dataset.source) {
        e.dataTransfer.setData("source", this.el.dataset.source)
      }
      e.dataTransfer.effectAllowed = "move"

      const ghost = document.createElement("div")
      ghost.className = "drag-ghost zone-token"
      ghost.style.background = color
      ghost.textContent = name
      ghost.id = "drag-ghost"
      document.body.appendChild(ghost)
      e.dataTransfer.setDragImage(ghost, ghost.offsetWidth / 2, ghost.offsetHeight / 2)

      setTimeout(() => ghost.remove(), 0)
    })

    this._cleanupTouch = makeTouchDraggable(this.el, {
      getData: () => {
        const data = {
          "entity-id": this.el.dataset.entityId,
          "entity-name": this.el.dataset.entityName,
        }
        if (this.el.dataset.source) data["source"] = this.el.dataset.source
        return data
      },
      createGhost: () => {
        const ghost = document.createElement("div")
        ghost.className = "drag-ghost zone-token"
        ghost.style.background = this.el.dataset.entityColor
        ghost.textContent = this.el.dataset.entityName
        return ghost
      },
    })
  },
  destroyed() {
    if (this._cleanupTouch) this._cleanupTouch()
  },
}

const ZoneDropTarget = {
  mounted() {
    this.el.addEventListener("dragover", (e) => {
      if (e.dataTransfer.types.includes("entity-id")) {
        e.preventDefault()
        e.dataTransfer.dropEffect = "move"
        this.el.classList.add("drop-hover")
      }
    })
    this.el.addEventListener("dragleave", (e) => {
      this.el.classList.remove("drop-hover")
    })
    this.el.addEventListener("drop", (e) => {
      e.preventDefault()
      this.el.classList.remove("drop-hover")
      const entityId = e.dataTransfer.getData("entity-id")
      const zoneId = this.el.dataset.zoneId
      if (entityId && zoneId) {
        this.pushEvent("move_to_zone", {
          entity_id: entityId,
          zone_id: zoneId,
        })
      }
    })

    registerDropTarget(this.el, {
      accepts: (data) => !!data["entity-id"],
      onDrop: (data) => {
        const zoneId = this.el.dataset.zoneId
        if (data["entity-id"] && zoneId) {
          this.pushEvent("move_to_zone", {
            entity_id: data["entity-id"],
            zone_id: zoneId,
          })
        }
      },
      onHover: (el) => el.classList.add("drop-hover"),
      onLeave: (el) => el.classList.remove("drop-hover"),
    })
  },
  destroyed() {
    unregisterDropTarget(this.el)
  },
}

const EventReorder = {
  mounted() {
    this._draggingId = null
    this._dropTarget = null

    this.el.addEventListener("dragstart", (e) => {
      const row = e.target.closest("[data-event-id]")
      if (!row || row.getAttribute("draggable") !== "true") { e.preventDefault(); return }
      e.dataTransfer.effectAllowed = "move"
      e.dataTransfer.setData("application/x-event-id", row.dataset.eventId)
      row.style.opacity = "0.3"
      this._draggingId = row.dataset.eventId
    })

    this.el.addEventListener("dragend", (e) => {
      this.el.querySelectorAll("[data-event-id]").forEach(r => r.style.opacity = "")
      this._clearIndicator()
      this._draggingId = null
      this._dropTarget = null
    })

    this.el.addEventListener("dragover", (e) => {
      if (!this._draggingId) return
      e.preventDefault()
      e.dataTransfer.dropEffect = "move"
      this._updateIndicator(e.target, e.clientY)
    })

    this.el.addEventListener("drop", (e) => {
      e.preventDefault()
      if (!this._draggingId || !this._dropTarget) return
      this._commitReorder()
    })

    this._touchStartY = 0
    this._touchActivated = false

    this.el.addEventListener("touchstart", (e) => {
      if (e.touches.length !== 1) return
      const touch = e.touches[0]
      const row = touch.target.closest("[data-event-id]")
      if (!row || row.getAttribute("draggable") !== "true") return

      this._touchStartY = touch.clientY
      this._touchStartX = touch.clientX
      this._touchActivated = false
      this._draggingId = row.dataset.eventId
      this._touchRow = row
    }, { passive: true })

    this._onTouchMove = (e) => {
      if (!this._draggingId) return
      const touch = e.touches[0]

      if (!this._touchActivated) {
        const dx = touch.clientX - this._touchStartX
        const dy = touch.clientY - this._touchStartY
        if (dx * dx + dy * dy < 64) return
        this._touchActivated = true
        if (this._touchRow) this._touchRow.style.opacity = "0.3"
      }

      e.preventDefault()
      const hitEl = document.elementFromPoint(touch.clientX, touch.clientY)
      this._updateIndicator(hitEl, touch.clientY)
    }

    this._onTouchEnd = () => {
      if (this._draggingId && this._touchActivated && this._dropTarget) {
        this._commitReorder()
      }
      this.el.querySelectorAll("[data-event-id]").forEach(r => r.style.opacity = "")
      this._clearIndicator()
      this._draggingId = null
      this._dropTarget = null
      this._touchActivated = false
      this._touchRow = null
    }

    this.el.addEventListener("touchmove", this._onTouchMove, { passive: false })
    this.el.addEventListener("touchend", this._onTouchEnd)
    this.el.addEventListener("touchcancel", this._onTouchEnd)
  },

  _updateIndicator(targetEl, clientY) {
    const row = targetEl && targetEl.closest("[data-event-id]")
    if (!row || row.dataset.eventId === this._draggingId) {
      this._clearIndicator()
      return
    }
    if (row.classList.contains("opacity-30")) {
      this._clearIndicator()
      return
    }
    const rect = row.getBoundingClientRect()
    const midY = rect.top + rect.height / 2
    const position = clientY < midY ? "before" : "after"
    this._showIndicator(row, position)
    this._dropTarget = { eventId: row.dataset.eventId, position }
  },

  _commitReorder() {
    const rows = Array.from(this.el.querySelectorAll("[data-event-id]"))
    const targetRow = rows.find(r => r.dataset.eventId === this._dropTarget.eventId)
    if (!targetRow) return

    const targetIdx = rows.indexOf(targetRow)
    let afterEventId

    if (this._dropTarget.position === "before") {
      const prevRow = rows[targetIdx - 1]
      afterEventId = prevRow ? prevRow.dataset.eventId : ""
    } else {
      afterEventId = this._dropTarget.eventId
    }

    this.pushEvent("reorder_event", {
      event_id: this._draggingId,
      after_event_id: afterEventId
    })

    this._clearIndicator()
    this._dropTarget = null
    this._draggingId = null
  },

  _showIndicator(row, position) {
    let indicator = this.el.querySelector(".event-drop-indicator")
    if (!indicator) {
      indicator = document.createElement("div")
      indicator.className = "event-drop-indicator"
      indicator.style.cssText = "height:3px;background:#f59e0b;border-radius:2px;margin:1px 8px;pointer-events:none;"
    }
    if (position === "before") {
      row.parentNode.insertBefore(indicator, row)
    } else {
      row.parentNode.insertBefore(indicator, row.nextSibling)
    }
  },

  _clearIndicator() {
    const ind = this.el.querySelector(".event-drop-indicator")
    if (ind) ind.remove()
  }
}

const StepReorder = {
  mounted() {
    this._draggingType = null
    this._draggingIndex = null
    this._draggingStepType = null
    this._dropTarget = null
    this._droppedInLane = false

    const lane = () => this.el.querySelector("#build-lane")

    this.el.addEventListener("dragstart", (e) => {
      const paletteBtn = e.target.closest("[data-step-type]")
      const stepRow = e.target.closest("[data-step-index]")

      if (paletteBtn && paletteBtn.getAttribute("draggable") === "true") {
        e.dataTransfer.effectAllowed = "copy"
        e.dataTransfer.setData("application/x-step-type", paletteBtn.dataset.stepType)
        this._draggingType = "palette"
        this._draggingStepType = paletteBtn.dataset.stepType
        this._droppedInLane = false
      } else if (stepRow && stepRow.getAttribute("draggable") === "true") {
        e.dataTransfer.effectAllowed = "move"
        e.dataTransfer.setData("application/x-step-index", stepRow.dataset.stepIndex)
        stepRow.style.opacity = "0.3"
        this._draggingType = "reorder"
        this._draggingIndex = stepRow.dataset.stepIndex
        this._droppedInLane = false
      }
    })

    this.el.addEventListener("dragend", (e) => {
      this._finishDrag(lane())
    })

    this.el.addEventListener("dragover", (e) => {
      const laneEl = lane()
      if (!laneEl) return

      const inLane = laneEl.contains(e.target)
      if (!inLane) {
        this._clearIndicator()
        return
      }

      const hasPaletteType = e.dataTransfer.types.includes("application/x-step-type")
      const hasStepIndex = e.dataTransfer.types.includes("application/x-step-index")
      if (!hasPaletteType && !hasStepIndex) return

      e.preventDefault()
      e.dataTransfer.dropEffect = hasPaletteType ? "copy" : "move"
      this._updateLaneIndicator(e.target, e.clientY, laneEl)
    })

    this.el.addEventListener("drop", (e) => {
      const laneEl = lane()
      if (!laneEl || !laneEl.contains(e.target)) return

      e.preventDefault()
      this._droppedInLane = true

      const paletteType = e.dataTransfer.getData("application/x-step-type")
      const stepIndex = e.dataTransfer.getData("application/x-step-index")
      this._commitDrop(paletteType, stepIndex)
    })

    // --- Touch support ---
    this._touchActivated = false
    this._touchRow = null

    this.el.addEventListener("touchstart", (e) => {
      if (e.touches.length !== 1) return
      const touch = e.touches[0]
      const paletteBtn = touch.target.closest("[data-step-type]")
      const stepRow = touch.target.closest("[data-step-index]")

      if (paletteBtn && paletteBtn.getAttribute("draggable") === "true") {
        this._draggingType = "palette"
        this._draggingStepType = paletteBtn.dataset.stepType
        this._touchRow = paletteBtn
      } else if (stepRow && stepRow.getAttribute("draggable") === "true") {
        this._draggingType = "reorder"
        this._draggingIndex = stepRow.dataset.stepIndex
        this._touchRow = stepRow
      } else {
        return
      }

      this._touchStartX = touch.clientX
      this._touchStartY = touch.clientY
      this._touchActivated = false
      this._droppedInLane = false
    }, { passive: true })

    this._onTouchMove = (e) => {
      if (!this._draggingType) return
      const touch = e.touches[0]

      if (!this._touchActivated) {
        const dx = touch.clientX - this._touchStartX
        const dy = touch.clientY - this._touchStartY
        if (dx * dx + dy * dy < 64) return
        this._touchActivated = true
        if (this._touchRow && this._draggingType === "reorder") {
          this._touchRow.style.opacity = "0.3"
        }
      }

      e.preventDefault()
      const laneEl = lane()
      if (!laneEl) return

      const hitEl = document.elementFromPoint(touch.clientX, touch.clientY)
      if (!hitEl || !laneEl.contains(hitEl)) {
        this._clearIndicator()
        return
      }
      this._updateLaneIndicator(hitEl, touch.clientY, laneEl)
    }

    this._onTouchEnd = () => {
      if (this._draggingType && this._touchActivated) {
        const laneEl = lane()
        if (this._dropTarget) {
          this._droppedInLane = true
          this._commitDrop(
            this._draggingType === "palette" ? this._draggingStepType : "",
            this._draggingType === "reorder" ? this._draggingIndex : ""
          )
        }
        this._finishDrag(laneEl)
      }
      this._draggingType = null
      this._draggingIndex = null
      this._draggingStepType = null
      this._touchActivated = false
      this._touchRow = null
    }

    this.el.addEventListener("touchmove", this._onTouchMove, { passive: false })
    this.el.addEventListener("touchend", this._onTouchEnd)
    this.el.addEventListener("touchcancel", this._onTouchEnd)
  },

  _updateLaneIndicator(targetEl, clientY, laneEl) {
    const stepRow = targetEl.closest("[data-step-index]")
    if (stepRow && stepRow.dataset.stepIndex === this._draggingIndex) {
      this._clearIndicator()
      return
    }

    if (stepRow) {
      const rect = stepRow.getBoundingClientRect()
      const midY = rect.top + rect.height / 2
      const position = clientY < midY ? "before" : "after"
      this._showIndicator(stepRow, position)
      this._dropTarget = { index: parseInt(stepRow.dataset.stepIndex), position }
    } else {
      const rows = laneEl.querySelectorAll("[data-step-index]")
      if (rows.length === 0) {
        this._dropTarget = { index: 0, position: "at" }
      } else {
        const lastRow = rows[rows.length - 1]
        this._showIndicator(lastRow, "after")
        this._dropTarget = { index: parseInt(lastRow.dataset.stepIndex) + 1, position: "at" }
      }
    }
  },

  _commitDrop(paletteType, stepIndex) {
    let targetPosition = this._dropTarget ? this._computeInsertIndex() : null

    if (paletteType) {
      const payload = { step_type: paletteType }
      if (targetPosition != null) payload.position = String(targetPosition)
      this.pushEvent("add_step", payload)
    } else if (stepIndex !== "") {
      const from = parseInt(stepIndex)
      let to = targetPosition != null ? targetPosition : from
      if (from < to) to = Math.max(0, to - 1)
      if (from !== to) {
        this.pushEvent("reorder_step", { from: String(from), to: String(to) })
      }
    }

    this._clearIndicator()
    this._dropTarget = null
  },

  _finishDrag(laneEl) {
    if (laneEl) laneEl.querySelectorAll("[data-step-index]").forEach(r => r.style.opacity = "")
    this._clearIndicator()

    if (this._draggingType === "reorder" && !this._droppedInLane && this._draggingIndex != null) {
      this.pushEvent("remove_step", { index: this._draggingIndex })
    }

    this._draggingType = null
    this._draggingIndex = null
    this._draggingStepType = null
    this._dropTarget = null
  },

  _computeInsertIndex() {
    if (!this._dropTarget) return null
    if (this._dropTarget.position === "at") return this._dropTarget.index
    if (this._dropTarget.position === "before") return this._dropTarget.index
    return this._dropTarget.index + 1
  },

  _showIndicator(row, position) {
    let indicator = this.el.querySelector(".step-drop-indicator")
    if (!indicator) {
      indicator = document.createElement("div")
      indicator.className = "step-drop-indicator"
      indicator.style.cssText = "height:3px;background:#f59e0b;border-radius:2px;margin:1px 0;pointer-events:none;"
    }
    if (position === "before") {
      row.parentNode.insertBefore(indicator, row)
    } else {
      row.parentNode.insertBefore(indicator, row.nextSibling)
    }
  },

  _clearIndicator() {
    const ind = this.el.querySelector(".step-drop-indicator")
    if (ind) ind.remove()
  }
}

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: () => ({
    _csrf_token: csrfToken,
    participant_id: localStorage.getItem("fate_participant_id"),
    participant_name: localStorage.getItem("fate_name"),
    participant_role: localStorage.getItem("fate_role"),
  }),
  hooks: {...colocatedHooks, SpringLayout, DraggableEntity, DropTarget, DraggableToken, ZoneDropTarget, EventReorder, StepReorder, MentionTypeahead},
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", _e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}

