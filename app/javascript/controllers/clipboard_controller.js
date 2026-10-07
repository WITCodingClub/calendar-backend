import { Controller } from "@hotwired/stimulus"

// Copies a value to the clipboard and says so on the button for two seconds.
export default class extends Controller {
  static targets = ["label"]
  static values = { text: String }

  async copy() {
    await navigator.clipboard.writeText(this.textValue)
    const label = this.hasLabelTarget ? this.labelTarget : this.element
    const original = label.textContent
    label.textContent = "Copied"
    clearTimeout(this.timer)
    this.timer = setTimeout(() => { label.textContent = original }, 2000)
  }

  disconnect() {
    clearTimeout(this.timer)
  }
}
