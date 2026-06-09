import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

export default class extends Controller {
  static values = {
    interval: { type: Number, default: 5000 },
    url: { type: String, default: "" }
  }

  connect() {
    this.scheduleNext()
  }

  disconnect() {
    clearTimeout(this.timer)
  }

  scheduleNext() {
    this.timer = setTimeout(() => this.tick(), this.intervalValue)
  }

  tick() {
    const url = this.urlValue || window.location.href
    Turbo.visit(url, { frame: this.element.id })
    this.scheduleNext()
  }
}
