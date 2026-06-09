import { Controller } from "@hotwired/stimulus"

// Auto-dismissing flash message banner.
export default class extends Controller {
  static values = { timeout: { type: Number, default: 5000 } }

  connect() {
    if (this.timeoutValue > 0) {
      this._timer = setTimeout(() => this.dismiss(), this.timeoutValue)
    }
  }

  disconnect() {
    clearTimeout(this._timer)
  }

  dismiss() {
    this.element.style.transition = "opacity 200ms ease"
    this.element.style.opacity = "0"
    setTimeout(() => this.element.remove(), 220)
  }
}
