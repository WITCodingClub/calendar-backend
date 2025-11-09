import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="semester-switcher"
export default class extends Controller {
  static targets = ["semester", "dropdown"]

  connect() {
    // Show the first (most recent) semester by default
    this.showSemester(0)
  }

  switch(event) {
    const selectedIndex = parseInt(event.target.value)
    this.showSemester(selectedIndex)
  }

  showSemester(index) {
    // Hide all semesters
    this.semesterTargets.forEach((semester) => {
      semester.classList.add("hidden")
    })

    // Show selected semester
    if (this.semesterTargets[index]) {
      this.semesterTargets[index].classList.remove("hidden")
    }

    // Update dropdown if it exists
    if (this.hasDropdownTarget) {
      this.dropdownTarget.value = index
    }
  }
}
