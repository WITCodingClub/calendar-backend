import { Controller } from "@hotwired/stimulus"

// Sidebar category collapse/expand controller
export default class extends Controller {
  static targets = ["chevron", "items"]

  connect() {
    const categoryId = this.element.dataset.categoryId

    if (categoryId) {
      // Check localStorage first
      const savedState = localStorage.getItem(`sidebar-category-${categoryId}`)

      if (savedState !== null) {
        // Use saved state if available
        if (savedState === "true") {
          this.collapse()
        }
      } else {
        // Default collapsed state for certain categories
        const defaultCollapsed = ['system_tools', 'owner_only']
        if (defaultCollapsed.includes(categoryId)) {
          this.collapse()
        }
      }
    }
  }

  toggle() {
    if (this.itemsTarget.classList.contains("hidden")) {
      this.expand()
    } else {
      this.collapse()
    }
  }

  collapse() {
    this.itemsTarget.classList.add("hidden")
    this.chevronTarget.classList.remove("rotate-0")
    this.chevronTarget.classList.add("-rotate-90")
    this.saveState(true)
  }

  expand() {
    this.itemsTarget.classList.remove("hidden")
    this.chevronTarget.classList.remove("-rotate-90")
    this.chevronTarget.classList.add("rotate-0")
    this.saveState(false)
  }

  saveState(collapsed) {
    const categoryId = this.element.dataset.categoryId
    if (categoryId) {
      localStorage.setItem(`sidebar-category-${categoryId}`, collapsed.toString())
    }
  }
}
