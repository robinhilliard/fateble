const SPRING_STRENGTH = 0.015
const REPULSION_STRENGTH = 0.4
const DAMPING = 0.6
const EDGE_MARGIN = 20
const MIN_VELOCITY = 0.05
const SETTLE_THRESHOLD = 0.3
const GAP = 20
const MAX_FORCE = 8
const MAX_VELOCITY = 12
const BORDER_INSET = 30
const BORDER_REPULSION = 0.3

export const SpringLayout = {
  mounted() {
    this.nodes = new Map()
    this.animFrame = null
    this.settled = false
    this.container = this.el
    this.dragging = null
    this.borderPerimeter = 0

    this.branchKey = this.el.dataset.sceneKey || "default"
    this.sceneId = this.el.dataset.sceneId || "default"

    this.collectNodes()
    this.initPositions()
    this.restorePositions()
    this.startLoop()

    this.el.addEventListener("dragover", (e) => {
      if (e.dataTransfer.types.includes("entity-id")) {
        e.preventDefault()
        e.dataTransfer.dropEffect = "move"
      }
    })
    this.el.addEventListener("drop", (e) => {
      if (e.target.closest(".zone-box")) return
      const entityId = e.dataTransfer.getData("entity-id")
      if (entityId) {
        e.preventDefault()
        this.pushEvent("remove_from_zone", { entity_id: entityId })
      }
    })

    this.el.addEventListener("mousedown", (e) => this.onMouseDown(e))
    window.addEventListener("mousemove", (e) => this.onMouseMove(e))
    window.addEventListener("mouseup", (e) => this.onMouseUp(e))
    this.el.addEventListener("dblclick", (e) => this.onDoubleClick(e))

    this._lastPerimeter = this.getBorderRect().perimeter

    this._resizeObserver = new ResizeObserver(() => {
      const { perimeter } = this.getBorderRect()
      const w = this.container.clientWidth || 1
      const h = this.container.clientHeight || 1

      // Rescale border positions proportionally
      if (this._lastPerimeter > 0 && perimeter !== this._lastPerimeter) {
        for (const [, node] of this.nodes) {
          if (node.onBorder && node.initialized) {
            const frac = node.borderPos / this._lastPerimeter
            node.borderPos = frac * perimeter
          }
        }
      }

      // Rescale free node positions proportionally
      if (this._lastW && this._lastH) {
        for (const [, node] of this.nodes) {
          if (!node.onBorder && node.initialized) {
            node.x = (node.x / this._lastW) * w
            node.y = (node.y / this._lastH) * h
          }
        }
      }

      this._lastPerimeter = perimeter
      this._lastW = w
      this._lastH = h
      this.settled = false
    })
    this._lastW = this.container.clientWidth
    this._lastH = this.container.clientHeight
    this._resizeObserver.observe(this.el)
  },

  updated() {
    const newSceneId = this.el.dataset.sceneId || "default"
    const sceneChanged = newSceneId !== this.sceneId

    this.savePositions()

    if (sceneChanged) {
      this.sceneId = newSceneId
    }

    this.collectNodes()
    this.initNewNodes()
    this.restorePositions()

    this.settled = false
  },

  destroyed() {
    if (this.animFrame) cancelAnimationFrame(this.animFrame)
    if (this._resizeObserver) this._resizeObserver.disconnect()
  },

  collectNodes() {
    const elements = this.el.querySelectorAll(".spring-element")
    const seen = new Set()

    elements.forEach((el) => {
      const id = el.dataset.elementId
      if (!id) return
      seen.add(id)

      if (!this.nodes.has(id)) {
        this.nodes.set(id, {
          el,
          id,
          x: 0,
          y: 0,
          vx: 0,
          vy: 0,
          width: 0,
          height: 0,
          anchor: el.dataset.anchor || "centre",
          pinned: el.dataset.pinned === "true",
          userPinned: false,
          onBorder: el.dataset.onBorder === "true",
          zoneOnly: el.dataset.zoneOnlyRepulsion === "true",
          borderPos: 0,
          borderVel: 0,
          initialized: false,
        })
      } else {
        const node = this.nodes.get(id)
        node.el = el
        node.anchor = el.dataset.anchor || "centre"
        if (el.dataset.pinned === "true") node.pinned = true
        node.onBorder = el.dataset.onBorder === "true"
        node.zoneOnly = el.dataset.zoneOnlyRepulsion === "true"
      }
    })

    for (const [id] of this.nodes) {
      if (!seen.has(id)) this.nodes.delete(id)
    }
  },

  // --- Border path geometry ---
  // The border is a rectangle inset by BORDER_INSET.
  // We parameterise it as a 1D position (0 to perimeter length).
  // Starting from top-left corner, going clockwise:
  //   0..innerW = top edge (left to right)
  //   innerW..innerW+innerH = right edge (top to bottom)
  //   innerW+innerH..2*innerW+innerH = bottom edge (right to left)
  //   2*innerW+innerH..perimeter = left edge (bottom to top)

  getBorderRect() {
    const w = this.container.clientWidth
    const h = this.container.clientHeight
    const x1 = BORDER_INSET
    const y1 = BORDER_INSET
    const x2 = w - BORDER_INSET
    const y2 = h - BORDER_INSET
    const innerW = x2 - x1
    const innerH = y2 - y1
    const perimeter = 2 * (innerW + innerH)
    return { x1, y1, x2, y2, innerW, innerH, perimeter }
  },

  borderPosToXY(pos) {
    const { x1, y1, x2, y2, innerW, innerH, perimeter } = this.getBorderRect()
    const p = ((pos % perimeter) + perimeter) % perimeter

    if (p < innerW) {
      return { x: x1 + p, y: y1 }
    } else if (p < innerW + innerH) {
      return { x: x2, y: y1 + (p - innerW) }
    } else if (p < 2 * innerW + innerH) {
      return { x: x2 - (p - innerW - innerH), y: y2 }
    } else {
      return { x: x1, y: y2 - (p - 2 * innerW - innerH) }
    }
  },

  borderPosToEdge(pos) {
    const { innerW, innerH, perimeter } = this.getBorderRect()
    const p = ((pos % perimeter) + perimeter) % perimeter

    if (p < innerW) return "top"
    if (p < innerW + innerH) return "right"
    if (p < 2 * innerW + innerH) return "bottom"
    return "left"
  },

  dockEdgeToBorderPos(dockEdge) {
    const { innerW, innerH } = this.getBorderRect()
    switch (dockEdge) {
      case "north": return innerW / 2
      case "east":  return innerW + innerH / 2
      case "south": return innerW + innerH + innerW / 2
      case "west":  return 2 * innerW + innerH + innerH / 2
      default:      return innerW + innerH + innerW / 2
    }
  },

  perimeterDistance(a, b) {
    const { perimeter } = this.getBorderRect()
    const d = ((b - a) % perimeter + perimeter) % perimeter
    return Math.min(d, perimeter - d)
  },

  // --- Anchor positions ---

  getAnchorPosition(anchor, w, h) {
    if (anchor === "scene") {
      const dockEdge = this.getDockEdge()
      switch (dockEdge) {
        case "south": return { x: w / 2, y: h * 0.33 }
        case "north": return { x: w / 2, y: h * 0.67 }
        case "west":  return { x: w * 0.67, y: h / 2 }
        case "east":  return { x: w * 0.33, y: h / 2 }
        default:      return { x: w / 2, y: h * 0.33 }
      }
    }

    if (anchor === "centre") {
      const sceneNode = this.nodes.get("scene-title")
      if (sceneNode && sceneNode.initialized) {
        return {
          x: sceneNode.x + sceneNode.width / 2,
          y: sceneNode.y + sceneNode.height / 2,
        }
      }
      return this.getAnchorPosition("scene", w, h)
    }

    if (anchor === "gm") {
      const gmBorderPos = this.getGmBorderPos()
      const pt = this.borderPosToXY(gmBorderPos)
      const dockEdge = this.getDockEdge()
      const inset = 80
      switch (dockEdge) {
        case "south": return { x: pt.x, y: pt.y - inset }
        case "north": return { x: pt.x, y: pt.y + inset }
        case "west":  return { x: pt.x + inset, y: pt.y }
        case "east":  return { x: pt.x - inset, y: pt.y }
        default:      return { x: pt.x, y: pt.y - inset }
      }
    }

    if (anchor.startsWith("controller-border-")) {
      const borderPos = parseFloat(anchor.replace("controller-border-", ""))
      const pt = this.borderPosToXY(borderPos)
      const dockEdge = this.getDockEdge()
      // Offset inward from the border
      return this.offsetInward(pt, 80)
    }

    return { x: w / 2, y: h / 2 }
  },

  offsetInward(pt, amount) {
    const w = this.container.clientWidth
    const h = this.container.clientHeight
    const cx = w / 2
    const cy = h / 2
    const dx = cx - pt.x
    const dy = cy - pt.y
    const dist = Math.sqrt(dx * dx + dy * dy) || 1
    return {
      x: pt.x + (dx / dist) * amount,
      y: pt.y + (dy / dist) * amount,
    }
  },

  getDockEdge() {
    for (const [, node] of this.nodes) {
      if (node.anchor === "gm-border") return node.el.dataset.dockEdge || "south"
    }
    return "south"
  },

  getGmBorderPos() {
    for (const [, node] of this.nodes) {
      if (node.anchor === "gm-border") return node.borderPos
    }
    return this.dockEdgeToBorderPos("south")
  },

  initPositions() {
    this.initNewNodes()
  },

  initNewNodes() {
    const w = this.container.clientWidth
    const h = this.container.clientHeight

    // Pass 1: init border nodes so controllers have positions
    const uninitBorder = Array.from(this.nodes.values()).filter(
      (n) => !n.initialized && n.onBorder
    )
    const gmNode = uninitBorder.find((n) => n.anchor === "gm-border")
    const playerNodes = uninitBorder.filter((n) => n.anchor !== "gm-border")

    if (gmNode) {
      const dockEdge = gmNode.el.dataset.dockEdge || "south"
      gmNode.borderPos = this.dockEdgeToBorderPos(dockEdge)
      const pt = this.borderPosToXY(gmNode.borderPos)
      gmNode.x = pt.x - (gmNode.el.offsetWidth || 60) / 2
      gmNode.y = pt.y - (gmNode.el.offsetHeight || 20) / 2
      gmNode.initialized = true
    }

    const { perimeter } = this.getBorderRect()
    const gmPos = gmNode
      ? gmNode.borderPos
      : this.dockEdgeToBorderPos("south")

    playerNodes.forEach((node, i) => {
      const count = playerNodes.length
      const spread = perimeter * 0.6
      const start = gmPos + (perimeter - spread) / 2
      const spacing = spread / (count + 1)
      node.borderPos = (start + spacing * (i + 1)) % perimeter
      const pt = this.borderPosToXY(node.borderPos)
      node.x = pt.x - (node.el.offsetWidth || 60) / 2
      node.y = pt.y - (node.el.offsetHeight || 20) / 2
      node.initialized = true
    })

    // Pass 2: init free nodes
    for (const [, node] of this.nodes) {
      if (node.initialized || node.onBorder) continue

      // Controlled entities start near their controller
      if (node.anchor.startsWith("controller-")) {
        const controllerId = node.el.dataset.controllerId
        const controllerNode = Array.from(this.nodes.values()).find(
          (bn) => bn.onBorder && bn.el.dataset.participantId === controllerId
        )
        if (controllerNode) {
          const pt = this.borderPosToXY(controllerNode.borderPos)
          const inward = this.offsetInward(pt, 100)
          const jitter = () => (Math.random() - 0.5) * 40
          node.x = inward.x + jitter()
          node.y = inward.y + jitter()
          node.initialized = true
          continue
        }
      }

      const anchor = this.getAnchorPosition(node.anchor, w, h)
      if (node.pinned) {
        node.x = anchor.x - (node.el.offsetWidth || 100) / 2
        node.y = anchor.y - (node.el.offsetHeight || 40) / 2
      } else {
        const jitter = () => (Math.random() - 0.5) * 60
        node.x = anchor.x + jitter()
        node.y = anchor.y + jitter()
      }
      node.initialized = true
    }
  },

  startLoop() {
    const tick = () => {
      this.animFrame = requestAnimationFrame(tick)
      if (this.settled && !this.dragging) return
      this.simulate()
      this.render()
    }
    this.animFrame = requestAnimationFrame(tick)
  },

  rectSeparation(a, b) {
    const acx = a.x + a.width / 2, acy = a.y + a.height / 2
    const bcx = b.x + b.width / 2, bcy = b.y + b.height / 2

    const halfW = (a.width + b.width) / 2 + GAP
    const halfH = (a.height + b.height) / 2 + GAP

    const dx = acx - bcx
    const dy = acy - bcy
    const penX = halfW - Math.abs(dx)
    const penY = halfH - Math.abs(dy)

    if (penX <= 0 || penY <= 0) return null
    return { dx, dy, penX, penY }
  },

  simulate() {
    const w = this.container.clientWidth
    const h = this.container.clientHeight
    const nodeList = Array.from(this.nodes.values())
    const borderNodes = nodeList.filter((n) => n.onBorder)
    const freeNodes = nodeList.filter((n) => !n.onBorder)

    for (const node of nodeList) {
      node.width = node.el.offsetWidth || 60
      node.height = node.el.offsetHeight || 20
    }

    // --- Simulate border nodes (1D perimeter springs) ---
    const { perimeter } = this.getBorderRect()

    for (const node of borderNodes) {
      if (node.anchor === "gm-border" || node === this.dragging?.node) continue

      let force = 0

      // Repel from all other border nodes along perimeter
      for (const other of borderNodes) {
        if (other.id === node.id) continue
        const dist = this.perimeterDistance(node.borderPos, other.borderPos)
        if (dist < 1) continue

        const repulsion = (perimeter * BORDER_REPULSION) / (dist * dist)
        const d = ((node.borderPos - other.borderPos) % perimeter + perimeter) % perimeter
        const sign = d < perimeter / 2 ? 1 : -1
        force += sign * Math.min(repulsion, MAX_FORCE)
      }

      node.borderVel = (node.borderVel + force) * DAMPING
      node.borderVel = Math.max(-MAX_VELOCITY, Math.min(MAX_VELOCITY, node.borderVel))
      if (Math.abs(node.borderVel) < MIN_VELOCITY) node.borderVel = 0

      node.borderPos = ((node.borderPos + node.borderVel) % perimeter + perimeter) % perimeter
    }

    // Update border node positions from borderPos, adjusting alignment per edge
    for (const node of borderNodes) {
      const pt = this.borderPosToXY(node.borderPos)
      const edge = this.borderPosToEdge(node.borderPos)

      switch (edge) {
        case "top":
          node.x = pt.x - node.width / 2
          node.y = pt.y
          break
        case "bottom":
          node.x = pt.x - node.width / 2
          node.y = pt.y - node.height
          break
        case "left":
          node.x = pt.x
          node.y = pt.y - node.height / 2
          break
        case "right":
          node.x = pt.x - node.width
          node.y = pt.y - node.height / 2
          break
      }
    }

    // --- Update anchors for controlled entities based on controller border positions ---
    for (const node of freeNodes) {
      if (node.anchor.startsWith("controller-")) {
        const controllerId = node.el.dataset.controllerId
        const controllerNode = borderNodes.find(
          (bn) => bn.el.dataset.participantId === controllerId
        )
        if (controllerNode) {
          node.anchor = `controller-border-${controllerNode.borderPos}`
        }
      }
    }

    // --- Simulate free nodes (2D springs) ---
    let totalMovement = 0

    for (const node of freeNodes) {
      if (node === this.dragging?.node) continue
      if (node.pinned) continue

      const isPinned = node.userPinned
      let fx = 0
      let fy = 0

      // Spring attraction to anchor (skip for pinned)
      // Force drops to zero within a dead zone so elements don't crush together
      if (!isPinned) {
        const anchor = this.getAnchorPosition(node.anchor, w, h)
        const anchorDx = anchor.x - (node.x + node.width / 2)
        const anchorDy = anchor.y - (node.y + node.height / 2)
        const dist = Math.sqrt(anchorDx * anchorDx + anchorDy * anchorDy)
        const deadZone = 100
        if (dist > deadZone) {
          const scale = (dist - deadZone) / dist
          fx += anchorDx * scale * SPRING_STRENGTH
          fy += anchorDy * scale * SPRING_STRENGTH
        }
      }

      // Bounding-box repulsion (zones only repel other zones)
      for (const other of nodeList) {
        if (other.id === node.id || other === this.dragging?.node) continue
        if (node.zoneOnly && !other.zoneOnly) continue
        if (!node.zoneOnly && other.zoneOnly) continue

        const pen = this.rectSeparation(node, other)
        if (!pen) continue

        if (pen.penX < pen.penY) {
          const sign = pen.dx >= 0 ? 1 : -1
          fx += sign * Math.min(pen.penX * REPULSION_STRENGTH, MAX_FORCE)
        } else {
          const sign = pen.dy >= 0 ? 1 : -1
          fy += sign * Math.min(pen.penY * REPULSION_STRENGTH, MAX_FORCE)
        }
      }

      // Edge repulsion
      if (node.x < EDGE_MARGIN)
        fx += Math.min((EDGE_MARGIN - node.x) * 0.1, MAX_FORCE)
      if (node.x + node.width > w - EDGE_MARGIN)
        fx -= Math.min((node.x + node.width - (w - EDGE_MARGIN)) * 0.1, MAX_FORCE)
      if (node.y < EDGE_MARGIN)
        fy += Math.min((EDGE_MARGIN - node.y) * 0.1, MAX_FORCE)
      if (node.y + node.height > h - EDGE_MARGIN)
        fy -= Math.min((node.y + node.height - (h - EDGE_MARGIN)) * 0.1, MAX_FORCE)

      const nodeDamping = isPinned ? DAMPING * 0.5 : DAMPING
      node.vx = (node.vx + fx) * nodeDamping
      node.vy = (node.vy + fy) * nodeDamping
      node.vx = Math.max(-MAX_VELOCITY, Math.min(MAX_VELOCITY, node.vx))
      node.vy = Math.max(-MAX_VELOCITY, Math.min(MAX_VELOCITY, node.vy))
      if (Math.abs(node.vx) < MIN_VELOCITY) node.vx = 0
      if (Math.abs(node.vy) < MIN_VELOCITY) node.vy = 0

      node.x += node.vx
      node.y += node.vy
      totalMovement += Math.abs(node.vx) + Math.abs(node.vy)
    }

    for (const node of borderNodes) {
      totalMovement += Math.abs(node.borderVel)
    }

    const nowSettled = totalMovement < SETTLE_THRESHOLD
    if (nowSettled && !this.settled) {
      this.savePositions()
    }
    this.settled = nowSettled
  },

  render() {
    for (const [, node] of this.nodes) {
      node.el.style.transform = `translate(${Math.round(node.x)}px, ${Math.round(node.y)}px)`
      node.el.style.position = "absolute"
      node.el.style.left = "0"
      node.el.style.top = "0"

      if (node.userPinned) {
        node.el.classList.add("user-pinned")
      } else {
        node.el.classList.remove("user-pinned")
      }
    }
  },

  // --- Drag ---

  onMouseDown(e) {
    const springEl = e.target.closest(".spring-element")
    if (!springEl) return
    const id = springEl.dataset.elementId
    const node = this.nodes.get(id)
    if (!node) return
    if (e.target.closest("button, a, input, select, textarea, .entity-circle, .zone-token")) return


    this.dragging = {
      node,
      startX: e.clientX - node.x,
      startY: e.clientY - node.y,
    }
    springEl.style.zIndex = "100"
    springEl.style.cursor = "grabbing"
    e.preventDefault()
  },

  onMouseMove(e) {
    if (!this.dragging) return
    const node = this.dragging.node
    node.x = e.clientX - this.dragging.startX
    node.y = e.clientY - this.dragging.startY
    node.vx = 0
    node.vy = 0

    // If dragging a border node, snap to nearest border position
    if (node.onBorder) {
      node.borderPos = this.xyToBorderPos(e.clientX, e.clientY)
      const pt = this.borderPosToXY(node.borderPos)
      const edge = this.borderPosToEdge(node.borderPos)

      switch (edge) {
        case "top":
          node.x = pt.x - node.width / 2
          node.y = pt.y
          break
        case "bottom":
          node.x = pt.x - node.width / 2
          node.y = pt.y - node.height
          break
        case "left":
          node.x = pt.x
          node.y = pt.y - node.height / 2
          break
        case "right":
          node.x = pt.x - node.width
          node.y = pt.y - node.height / 2
          break
      }
    }

    this.settled = false
    this.render()
  },

  onMouseUp(e) {
    if (!this.dragging) return
    this.dragging.node.el.style.zIndex = ""
    this.dragging.node.el.style.cursor = ""
    this.dragging = null
    this.settled = false
    this.savePositions()
  },

  xyToBorderPos(px, py) {
    const { x1, y1, x2, y2, innerW, innerH } = this.getBorderRect()

    // Find closest point on the border rectangle
    const candidates = [
      { pos: Math.max(0, Math.min(innerW, px - x1)), side: "top" },
      { pos: innerW + Math.max(0, Math.min(innerH, py - y1)), side: "right" },
      { pos: innerW + innerH + Math.max(0, Math.min(innerW, x2 - px)), side: "bottom" },
      { pos: 2 * innerW + innerH + Math.max(0, Math.min(innerH, y2 - py)), side: "left" },
    ]

    const points = candidates.map((c) => {
      const pt = this.borderPosToXY(c.pos)
      const dx = px - pt.x
      const dy = py - pt.y
      return { pos: c.pos, dist: dx * dx + dy * dy }
    })

    return points.reduce((a, b) => (a.dist < b.dist ? a : b)).pos
  },

  // --- Pin/unpin ---

  onDoubleClick(e) {
    const springEl = e.target.closest(".spring-element")
    if (!springEl) return
    if (e.target.closest("button, a, input, select, textarea, .entity-circle, .zone-token")) return


    const id = springEl.dataset.elementId
    const node = this.nodes.get(id)
    if (!node || node.onBorder) return

    if (node.pinned) return

    node.userPinned = !node.userPinned
    node.vx = 0
    node.vy = 0
    this.settled = false
    this.render()
    this.savePositions()
  },

  // --- Persist positions to localStorage ---
  // Player positions (border + controlled entities) persist across scenes.
  // Scene elements (uncontrolled entities, aspects, scene title) are per-scene.

  tableStorageKey() {
    return `fate-layout:${this.branchKey}:table`
  },

  sceneStorageKey() {
    return `fate-layout:${this.branchKey}:scene:${this.sceneId}`
  },

  isSceneElement(node) {
    if (node.onBorder) return false
    if (node.anchor.startsWith("controller-")) return false
    if (node.id === "scene-title") return false
    return true
  },

  savePositions() {
    const w = this.container.clientWidth || 1
    const h = this.container.clientHeight || 1

    let tableData = {}
    let sceneData = {}
    try {
      const rawTable = localStorage.getItem(this.tableStorageKey())
      if (rawTable) tableData = JSON.parse(rawTable)
      const rawScene = localStorage.getItem(this.sceneStorageKey())
      if (rawScene) sceneData = JSON.parse(rawScene)
    } catch (_) {}

    for (const [id, node] of this.nodes) {
      const entry = node.onBorder
        ? { borderPos: node.borderPos, userPinned: node.userPinned }
        : { nx: node.x / w, ny: node.y / h, userPinned: node.userPinned }

      if (this.isSceneElement(node)) {
        sceneData[id] = entry
      } else {
        tableData[id] = entry
      }
    }

    try {
      localStorage.setItem(this.tableStorageKey(), JSON.stringify(tableData))
      localStorage.setItem(this.sceneStorageKey(), JSON.stringify(sceneData))
    } catch (_) {}
  },

  restorePositions() {
    let tableData = {}
    let sceneData = {}
    try {
      const rawTable = localStorage.getItem(this.tableStorageKey())
      if (rawTable) tableData = JSON.parse(rawTable)
      const rawScene = localStorage.getItem(this.sceneStorageKey())
      if (rawScene) sceneData = JSON.parse(rawScene)
    } catch (_) {
      return
    }

    const merged = { ...tableData, ...sceneData }
    const w = this.container.clientWidth || 1
    const h = this.container.clientHeight || 1

    for (const [id, node] of this.nodes) {
      const saved = merged[id]
      if (!saved) continue

      if (node.onBorder && saved.borderPos != null) {
        node.borderPos = saved.borderPos
        const pt = this.borderPosToXY(node.borderPos)
        const edge = this.borderPosToEdge(node.borderPos)
        switch (edge) {
          case "top":    node.x = pt.x - node.width / 2; node.y = pt.y; break
          case "bottom": node.x = pt.x - node.width / 2; node.y = pt.y - node.height; break
          case "left":   node.x = pt.x; node.y = pt.y - node.height / 2; break
          case "right":  node.x = pt.x - node.width; node.y = pt.y - node.height / 2; break
        }
      } else if (saved.nx != null) {
        node.x = saved.nx * w
        node.y = saved.ny * h
      }

      if (saved.userPinned) {
        node.userPinned = true
      }
    }
  },
}
