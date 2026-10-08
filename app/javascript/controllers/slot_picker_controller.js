import { Controller } from "@hotwired/stimulus"

// Shows the time that the guest picked on a meeting link page, next to the
// submit button, because the picked time can be in a closed day section.
export default class extends Controller {
  static targets = ["summary"]

  choose({ params: { label } }) {
    if (this.hasSummaryTarget) this.summaryTarget.textContent = `You picked ${label}.`
  }
}
