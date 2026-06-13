import { Controller } from "@hotwired/stimulus"

// Collapsible navigation category in the admin sidebar.
export default class extends Controller {
  static targets = ["items", "chevron"]

  toggle() {
    const collapsed = this.itemsTarget.classList.toggle("hidden")
    this.chevronTarget.classList.toggle("rotate-180", !collapsed)
  }
}
