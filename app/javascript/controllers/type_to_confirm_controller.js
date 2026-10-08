import { Controller } from "@hotwired/stimulus"

// A delete dialog. The submit button turns on only when the input matches
// the expected text, so a slip of the mouse cannot delete a record.
export default class extends Controller {
  static targets = ["dialog", "input", "submit"]
  static values = { expected: String }

  open() {
    this.inputTarget.value = ""
    this.check()
    this.dialogTarget.showModal()
    this.inputTarget.focus()
  }

  close() {
    this.dialogTarget.close()
  }

  // A click on the dialog element itself is a click on the backdrop.
  backdropClose(event) {
    if (event.target === this.dialogTarget) this.close()
  }

  check() {
    const matches = this.inputTarget.value.trim().toLowerCase() === this.expectedValue.trim().toLowerCase()
    this.submitTarget.disabled = !matches
  }
}
