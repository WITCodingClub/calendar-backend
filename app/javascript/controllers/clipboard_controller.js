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

  disconnect() {
    clearTimeout(this.timer)
  }

  // private

  report(label, message) {
    const element = this.hasLabelTarget ? this.labelTarget : this.element
    if (this.original === undefined) this.original = element.textContent
    element.textContent = label

    // A screen reader announces a change to the status text. Set the same
    // message on each click, so a second click is announced too.
    if (this.hasStatusTarget) {
      this.statusTarget.textContent = ""
      requestAnimationFrame(() => { this.statusTarget.textContent = message })
    }

    clearTimeout(this.timer)
    this.timer = setTimeout(() => {
      element.textContent = this.original
      this.original = undefined
      if (this.hasStatusTarget) this.statusTarget.textContent = ""
    }, 2000)
  }
}
