import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="auto-refresh"
// Auto-refreshes a turbo frame at a specified interval
// Usage: <turbo-frame data-controller="auto-refresh" data-auto-refresh-interval-value="3000">
export default class extends Controller {
  static values = {
    interval: { type: Number, default: 3000 }
  }

  connect() {
    this.startRefreshing()
  }

  disconnect() {
    this.stopRefreshing()
  }

  startRefreshing() {
    this.refreshTimer = setInterval(() => {
      this.refresh()
    }, this.intervalValue)
  }

  stopRefreshing() {
    if (this.refreshTimer) {
      clearInterval(this.refreshTimer)
    }
  }

  refresh() {
    // If this element is a turbo-frame, set its src to trigger a reload
    if (this.element.tagName === "TURBO-FRAME") {
      // Set src to current page URL to reload the frame
      this.element.src = window.location.href
    }
  }
}
