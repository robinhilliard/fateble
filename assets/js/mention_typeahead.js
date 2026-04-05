import Tribute from "tributejs"

function parseCatalog(el) {
  const raw = el.dataset.mentionCatalog
  if (!raw) return {entities: [], hashtags: []}
  try {
    return JSON.parse(raw)
  } catch {
    return {entities: [], hashtags: []}
  }
}

function buildTribute(catalog) {
  const entities = (catalog.entities || [])
    .map((e) => ({
      key: e.name || "",
      value: e.name || "",
      id: e.id,
    }))
    .filter((e) => e.key.length > 0)

  const tags = (catalog.hashtags || []).map((t) => ({
    key: `#${t}`,
    value: t,
  }))

  return new Tribute({
    collection: [
      {
        trigger: "@",
        values: entities,
        lookup: "key",
        fillAttr: "value",
        allowSpaces: true,
        menuShowMinLength: 0,
        selectTemplate(item) {
          return `@${item.original.value}`
        },
      },
      {
        trigger: "#",
        values: tags,
        lookup: "key",
        fillAttr: "value",
        menuShowMinLength: 0,
        selectTemplate(item) {
          return `#${item.original.value}`
        },
        menuItemTemplate(item) {
          return `#${item.original.value}`
        },
      },
    ],
  })
}

export const MentionTypeahead = {
  mounted() {
    this.tribute = null
    this._lastCatalog = null
    this._attach()
  },
  updated() {
    const current = this.el.dataset.mentionCatalog
    if (current !== this._lastCatalog) {
      this._detach()
      this._attach()
    }
  },
  destroyed() {
    this._detach()
  },
  _detach() {
    if (this._onReplaced) {
      this.el.removeEventListener("tribute-replaced", this._onReplaced)
      this._onReplaced = null
    }
    if (this.tribute) {
      try {
        this.tribute.detach(this.el)
      } catch (_) {
        /* ignore */
      }
      this.tribute = null
    }
  },
  _attach() {
    this._lastCatalog = this.el.dataset.mentionCatalog
    const catalog = parseCatalog(this.el)
    this.tribute = buildTribute(catalog)
    this.tribute.attach(this.el)

    this._onReplaced = () => {
      this.el.dispatchEvent(new Event("input", { bubbles: true }))
    }
    this.el.addEventListener("tribute-replaced", this._onReplaced)
  },
}
