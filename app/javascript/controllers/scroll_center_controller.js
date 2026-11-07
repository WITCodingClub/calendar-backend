import { Controller } from "@hotwired/stimulus"

// Scrolls a box that is wider than the screen so its center target is in the
// middle. The prerequisite map uses it to start on the selected course.
export default class extends Controller {
  static targets = ["center"]

  connect() {
    if (!this.hasCenterTarget) return

    const box = this.element.getBoundingClientRect()
    const target = this.centerTarget.getBoundingClientRect()
    const left = target.left - box.left + this.element.scrollLeft
    this.element.scrollLeft = left + (target.width / 2) - (box.width / 2)
  }
}
