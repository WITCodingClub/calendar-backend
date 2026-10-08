import { Controller } from "@hotwired/stimulus"

// Submits an admin filter form. Typing waits for a pause; a select or a
// checkbox submits at once.
export default class extends Controller {
  static values = { delay: { type: Number, default: 300 } }

  disconnect() {
    clearTimeout(this.timer)
  }

  submitLater() {
    clearTimeout(this.timer)
    this.timer = setTimeout(() => this.submit(), this.delayValue)
  }

  submit() {
    clearTimeout(this.timer)
    this.element.requestSubmit()
  }
}
