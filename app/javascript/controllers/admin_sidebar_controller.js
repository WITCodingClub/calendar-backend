import { Controller } from "@hotwired/stimulus"

// Manages the admin navigation sidebar — open/close on mobile, keyboard shortcut.
export default class extends Controller {
  static targets = ["overlay"]

  open() {
    this.overlayTarget.classList.remove("hidden")
    document.body.classList.add("overflow-hidden")
  }

  close() {
    this.overlayTarget.classList.add("hidden")
    document.body.classList.remove("overflow-hidden")
  }

  // Close on Escape key
  keydown(event) {
    if (event.key === "Escape") this.close()
  }
}
