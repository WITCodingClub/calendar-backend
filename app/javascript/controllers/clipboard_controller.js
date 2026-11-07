import { Controller } from "@hotwired/stimulus"

// Copies a value to the clipboard and says so on the button for two seconds.
//
// Optional targets:
// - status: a role="status" element. It tells a screen reader the result.
// - source: a read-only field that holds the value. When the copy fails, it
//   gets the focus with the value selected, so the person can copy it by hand.
export default class extends Controller {
  static targets = ["label", "status", "source"]
  static values = { text: String }

  async copy() {
    try {
      // navigator.clipboard is undefined outside a secure context. The
      // TypeError comes here too.
      await navigator.clipboard.writeText(this.textValue)
      this.report("Copied", "Copied to the clipboard.")
    } catch {
      if (this.hasSourceTarget) {
        this.sourceTarget.focus()
        this.sourceTarget.select()
        this.report("Copy failed", "Could not copy. The text is selected. Copy it with the keyboard.")
      } else {
        this.report("Copy failed", "Could not copy.")
      }
    }
  }

  // Selects the whole value of a read-only field, so it is easy to copy by hand.
  select(event) {
    event.currentTarget.select()
  }

  // Turbo copies the page into its cache before the controller disconnects.
  // Put the button back first, so a page restored with Back does not keep
  // "Copied" as its label.
  connect() {
    this.reset = this.reset.bind(this)
    document.addEventListener("turbo:before-cache", this.reset)
  }

  disconnect() {
    document.removeEventListener("turbo:before-cache", this.reset)
    this.reset()
  }

  // private

  get labelElement() {
    return this.hasLabelTarget ? this.labelTarget : this.element
  }

  report(label, message) {
    this.reset()
    this.original = this.labelElement.textContent
    this.labelElement.textContent = label

    // A screen reader announces a change to the status text. reset() empties
    // it first, so a second click with the same message is announced too.
    if (this.hasStatusTarget) {
      this.announceTimer = setTimeout(() => { this.statusTarget.textContent = message }, 50)
    }

    this.timer = setTimeout(() => this.reset(), 2000)
  }

  reset() {
    clearTimeout(this.timer)
    clearTimeout(this.announceTimer)
    if (this.original !== undefined) this.labelElement.textContent = this.original
    this.original = undefined
    if (this.hasStatusTarget) this.statusTarget.textContent = ""
  }
}
