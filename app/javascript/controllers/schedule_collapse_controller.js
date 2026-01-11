import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="schedule-collapse"
export default class extends Controller {
  static targets = ["content", "chevron", "termSelect", "termSchedule"]

  connect() {
    // Start collapsed
    this.collapsed = true
  }

  toggle() {
    this.collapsed = !this.collapsed

    if (this.hasContentTarget) {
      this.contentTarget.style.display = this.collapsed ? "none" : "block"
    }

    if (this.hasChevronTarget) {
      this.chevronTarget.style.transform = this.collapsed ? "rotate(-90deg)" : "rotate(0deg)"
    }
  }

  switchTerm(event) {
    const selectedTermId = event.target.value

    // Hide all term schedules
    this.termScheduleTargets.forEach((schedule) => {
      schedule.classList.add("hidden")
    })

    // Show selected term schedule
    const selectedSchedule = this.termScheduleTargets.find(
      (schedule) => schedule.dataset.termId === selectedTermId
    )
    if (selectedSchedule) {
      selectedSchedule.classList.remove("hidden")
    }
  }
}
