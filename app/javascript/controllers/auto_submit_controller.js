import { Controller } from "@hotwired/stimulus"

// Submits the form when a field changes, for a form with no submit button.
export default class extends Controller {
  submit() {
    this.element.requestSubmit()
  }
}
