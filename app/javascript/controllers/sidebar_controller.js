import { Controller } from "@hotwired/stimulus"

// Sidebar collapse/expand controller
export default class extends Controller {
  static targets = ["text", "icon", "overlay", "drawer"]
  static values = { collapsed: Boolean }

  connect() {
    // Restore collapsed state from localStorage
    const savedState = localStorage.getItem("sidebarCollapsed")
    if (savedState !== null) {
      this.collapsedValue = savedState === "true"
    }
    this.updateState()
  }

  toggle() {
    this.collapsedValue = !this.collapsedValue
    this.updateState()
    this.saveState()
  }

  openMobile() {
    if (this.hasOverlayTarget) {
      this.overlayTarget.classList.remove("hidden")
    }
    if (this.hasDrawerTarget) {
      this.drawerTarget.classList.remove("-translate-x-full")
    }
  }

  closeMobile() {
    if (this.hasOverlayTarget) {
      this.overlayTarget.classList.add("hidden")
    }
    if (this.hasDrawerTarget) {
      this.drawerTarget.classList.add("-translate-x-full")
    }
  }

  updateState() {
    const elements = this.element.querySelectorAll("[data-sidebar-collapsed]")
    elements.forEach(el => {
      if (this.collapsedValue) {
        el.setAttribute("data-sidebar-collapsed", "true")
      } else {
        el.removeAttribute("data-sidebar-collapsed")
      }
    })

    // Update main content margin
    const mainContent = document.querySelector("main.admin-content")
    if (mainContent) {
      if (this.collapsedValue) {
        mainContent.classList.remove("lg:ml-64")
        mainContent.classList.add("lg:ml-16")
      } else {
        mainContent.classList.remove("lg:ml-16")
        mainContent.classList.add("lg:ml-64")
      }
    }
  }

  saveState() {
    localStorage.setItem("sidebarCollapsed", this.collapsedValue.toString())

    // Save to session via AJAX (optional, for server-side persistence)
    fetch("/admin/sidebar/toggle", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": document.querySelector("[name='csrf-token']").content
      },
      body: JSON.stringify({ collapsed: this.collapsedValue })
    }).catch(() => {
      // Ignore errors - localStorage is primary
    })
  }
}
