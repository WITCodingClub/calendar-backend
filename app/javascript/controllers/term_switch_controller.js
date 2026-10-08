import { Controller } from "@hotwired/stimulus"

// Shows the panel for the term picked in the select and hides the others.
export default class extends Controller {
  static targets = ["select", "panel"]

  connect() {
    this.show()
  }

  show() {
    const termId = this.hasSelectTarget ? this.selectTarget.value : null
    this.panelTargets.forEach((panel, index) => {
      const visible = termId ? panel.dataset.termId === termId : index === 0
      panel.hidden = !visible
    })
  }
}
