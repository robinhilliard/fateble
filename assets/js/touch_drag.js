const DRAG_THRESHOLD = 8

let activeDrag = null
const dropTargets = new Map()

export function registerDropTarget(el, opts) {
  dropTargets.set(el, opts)
}

export function unregisterDropTarget(el) {
  dropTargets.delete(el)
}

function findDropTarget(hitEl, data) {
  if (!hitEl) return null

  let matches = []
  for (const [targetEl, targetOpts] of dropTargets) {
    if (targetEl.contains(hitEl) && targetOpts.accepts(data)) {
      matches.push({ el: targetEl, opts: targetOpts })
    }
  }

  if (matches.length > 1) {
    matches = matches.filter(
      (m) => !matches.some((other) => other.el !== m.el && m.el.contains(other.el))
    )
  }

  return matches[0] || null
}

export function makeTouchDraggable(el, opts) {
  let startX, startY, ghost, activated, currentTarget

  function onTouchStart(e) {
    if (e.touches.length !== 1) return
    const touch = e.touches[0]
    startX = touch.clientX
    startY = touch.clientY
    activated = false
    currentTarget = null

    const data = opts.getData()
    if (!data) return

    activeDrag = { data, el }

    document.addEventListener("touchmove", onTouchMove, { passive: false })
    document.addEventListener("touchend", onTouchEnd)
    document.addEventListener("touchcancel", onTouchCancel)
  }

  function onTouchMove(e) {
    if (!activeDrag) return
    const touch = e.touches[0]

    if (!activated) {
      const dx = touch.clientX - startX
      const dy = touch.clientY - startY
      if (dx * dx + dy * dy < DRAG_THRESHOLD * DRAG_THRESHOLD) return
      activated = true
      ghost = opts.createGhost(activeDrag.data)
      ghost.style.position = "fixed"
      ghost.style.pointerEvents = "none"
      ghost.style.zIndex = "9999"
      document.body.appendChild(ghost)
      if (opts.onDragStart) opts.onDragStart()
    }

    e.preventDefault()

    ghost.style.left = touch.clientX - ghost.offsetWidth / 2 + "px"
    ghost.style.top = touch.clientY - ghost.offsetHeight / 2 + "px"

    ghost.style.display = "none"
    const hitEl = document.elementFromPoint(touch.clientX, touch.clientY)
    ghost.style.display = ""

    const foundTarget = findDropTarget(hitEl, activeDrag.data)

    if (currentTarget && currentTarget.el !== foundTarget?.el) {
      currentTarget.opts.onLeave(currentTarget.el)
    }
    if (foundTarget && foundTarget.el !== currentTarget?.el) {
      foundTarget.opts.onHover(foundTarget.el)
    }
    currentTarget = foundTarget
  }

  function finish(dropped) {
    removeListeners()
    if (!activated) {
      activeDrag = null
      return
    }
    if (dropped && currentTarget) {
      currentTarget.opts.onDrop(activeDrag.data, currentTarget.el)
    }
    if (currentTarget) currentTarget.opts.onLeave(currentTarget.el)
    if (ghost) {
      ghost.remove()
      ghost = null
    }
    if (opts.onDragEnd) opts.onDragEnd()
    activeDrag = null
    currentTarget = null
  }

  function onTouchEnd() {
    finish(true)
  }

  function onTouchCancel() {
    finish(false)
  }

  function removeListeners() {
    document.removeEventListener("touchmove", onTouchMove)
    document.removeEventListener("touchend", onTouchEnd)
    document.removeEventListener("touchcancel", onTouchCancel)
  }

  el.addEventListener("touchstart", onTouchStart, { passive: true })

  return () => {
    el.removeEventListener("touchstart", onTouchStart)
    removeListeners()
    if (ghost) {
      ghost.remove()
      ghost = null
    }
  }
}
