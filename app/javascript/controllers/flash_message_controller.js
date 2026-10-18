import { Controller } from "@hotwired/stimulus"

// Flash message banner. With a timeout above zero it closes itself. The timer
// stops while the pointer or the focus is on the message, and starts again
// from the full timeout when both leave. A timeout of 0 keeps the message
// until the user closes it.
export default class extends Controller {
  static values = { timeout: { type: Number, default: 5000 } }

  connect() {
    this._hovered = false
    this._focused = false
    this._pause = this.pause.bind(this)
    this._resume = this.resume.bind(this)
    this.element.addEventListener("mouseenter", this._pause)
    this.element.addEventListener("mouseleave", this._resume)
    this.element.addEventListener("focusin", this._pause)
    this.element.addEventListener("focusout", this._resume)
    this.start()
  }

  disconnect() {
    clearTimeout(this._timer)
    this.element.removeEventListener("mouseenter", this._pause)
    this.element.removeEventListener("mouseleave", this._resume)
    this.element.removeEventListener("focusin", this._pause)
    this.element.removeEventListener("focusout", this._resume)
  }

  start() {
    clearTimeout(this._timer)
    if (this.timeoutValue > 0) {
      this._timer = setTimeout(() => this.dismiss(), this.timeoutValue)
    }
  }

  pause(event) {
    if (event.type === "mouseenter") this._hovered = true
    if (event.type === "focusin") this._focused = true
    clearTimeout(this._timer)
  }

  resume(event) {
    if (event.type === "mouseleave") this._hovered = false
    // focusout fires before focus moves; relatedTarget is the next element.
    if (event.type === "focusout" && !this.element.contains(event.relatedTarget)) this._focused = false
    if (!this._hovered && !this._focused) this.start()
  }

  dismiss() {
    clearTimeout(this._timer)
    this.element.style.transition = "opacity 200ms ease"
    this.element.style.opacity = "0"
    setTimeout(() => this.element.remove(), 220)
  }
}
