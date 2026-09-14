import { Controller } from "@hotwired/stimulus"

// Opens and closes the admin navigation overlay on small screens.
// Attached to <body> in layouts/admin; Escape and Turbo's before-cache
// event are wired to close() there.
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
}
