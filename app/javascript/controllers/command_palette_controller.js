import { Controller } from "@hotwired/stimulus"

// ⌘K command palette for quick admin navigation.
export default class extends Controller {
  static targets = ["backdrop", "panel", "input", "results"]

  connect() {
    this._onKeydown = this._globalKeydown.bind(this)
    document.addEventListener("keydown", this._onKeydown)
    this._activeIndex = -1
  }

  disconnect() {
    document.removeEventListener("keydown", this._onKeydown)
  }

  open() {
    this.backdropTarget.classList.remove("opacity-0", "pointer-events-none")
    this.panelTarget.classList.remove("opacity-0", "pointer-events-none")
    this.inputTarget.value = ""
    this.filter()
    this.inputTarget.focus()
    this._activeIndex = -1
  }

  close() {
    this.backdropTarget.classList.add("opacity-0", "pointer-events-none")
    this.panelTarget.classList.add("opacity-0", "pointer-events-none")
    this.inputTarget.blur()
  }

  filter() {
    const query = this.inputTarget.value.toLowerCase().trim()
    this._items().forEach(item => {
      const label = item.dataset.label || ""
      item.style.display = (!query || label.includes(query)) ? "" : "none"
    })
    this._activeIndex = -1
    this._highlight(-1)
  }

  keydown(event) {
    const visible = this._visibleItems()
    if (event.key === "ArrowDown") {
      event.preventDefault()
      this._activeIndex = Math.min(this._activeIndex + 1, visible.length - 1)
      this._highlight(this._activeIndex)
    } else if (event.key === "ArrowUp") {
      event.preventDefault()
      this._activeIndex = Math.max(this._activeIndex - 1, 0)
      this._highlight(this._activeIndex)
    } else if (event.key === "Enter") {
      event.preventDefault()
      if (visible[this._activeIndex]) visible[this._activeIndex].click()
    } else if (event.key === "Escape") {
      this.close()
    }
  }

  _globalKeydown(event) {
    if ((event.metaKey || event.ctrlKey) && event.key === "k") {
      event.preventDefault()
      this.open()
    }
  }

  _items() {
    return Array.from(this.resultsTarget.querySelectorAll(".command-palette-item"))
  }

  _visibleItems() {
    return this._items().filter(el => el.style.display !== "none")
  }

  _highlight(index) {
    this._visibleItems().forEach((el, i) => {
      el.classList.toggle("bg-surface-container-high", i === index)
    })
  }
}
