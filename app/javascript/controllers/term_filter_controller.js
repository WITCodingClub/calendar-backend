import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["search", "option", "noResults", "input"]

  filter() {
    const query = this.searchTarget.value.toLowerCase().trim()
    let visibleCount = 0

    this.optionTargets.forEach(option => {
      const termName = option.dataset.termName
      const matches = termName.includes(query)

      option.classList.toggle("hidden", !matches)
      if (matches) visibleCount++
    })

    // Show "no results" message if nothing matches
    this.noResultsTarget.classList.toggle("hidden", visibleCount > 0)
  }

  select(event) {
    // Update the hidden input with the selected term ID
    if (this.hasInputTarget) {
      this.inputTarget.value = event.target.value
    }
  }
}
