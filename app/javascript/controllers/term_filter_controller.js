import { Controller } from "@hotwired/stimulus"

// Filters the term list on the finals upload form as the admin types.
export default class extends Controller {
  static targets = ["search", "option", "noResults"]

  filter() {
    const query = this.searchTarget.value.trim().toLowerCase()
    let shown = 0
    this.optionTargets.forEach(option => {
      const visible = !query || option.dataset.termName.includes(query)
      option.hidden = !visible
      if (visible) shown++
    })
    this.noResultsTarget.hidden = shown > 0
  }
}
