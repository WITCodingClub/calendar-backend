import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="delete-confirmation"
export default class extends Controller {
  static targets = ["modal", "input", "confirmButton", "errorMessage"]
  static values = {
    confirmText: String,
    deleteUrl: String,
    itemType: { type: String, default: "item" }
  }

  connect() {
    // Create modal backdrop on connect
    this.createModal()
  }

  disconnect() {
    // Clean up modal when controller is disconnected
    this.removeModal()
  }

  // Show the confirmation modal
  show(event) {
    event.preventDefault()
    this.modalTarget.classList.remove("hidden")
    this.inputTarget.value = ""
    this.inputTarget.focus()
    this.updateConfirmButton()
  }

  // Hide the confirmation modal
  hide(event) {
    event.preventDefault()
    this.modalTarget.classList.add("hidden")
    this.inputTarget.value = ""
    this.errorMessageTarget.classList.add("hidden")
  }

  // Check if the input matches the confirmation text
  checkInput() {
    this.updateConfirmButton()
    this.errorMessageTarget.classList.add("hidden")
  }

  // Update confirm button state based on input
  updateConfirmButton() {
    const matches = this.inputTarget.value === this.confirmTextValue
    this.confirmButtonTarget.disabled = !matches

    if (matches) {
      this.confirmButtonTarget.classList.remove("opacity-50", "cursor-not-allowed")
      this.confirmButtonTarget.classList.add("cursor-pointer")
    } else {
      this.confirmButtonTarget.classList.add("opacity-50", "cursor-not-allowed")
      this.confirmButtonTarget.classList.remove("cursor-pointer")
    }
  }

  // Confirm deletion and submit the form
  async confirm(event) {
    event.preventDefault()

    if (this.inputTarget.value !== this.confirmTextValue) {
      this.errorMessageTarget.textContent = "Text does not match. Please try again."
      this.errorMessageTarget.classList.remove("hidden")
      return
    }

    // Find and submit the form
    const form = this.element.querySelector("form")
    if (form) {
      form.submit()
    }
  }

  // Close modal when clicking backdrop
  closeOnBackdrop(event) {
    if (event.target === this.modalTarget) {
      this.hide(event)
    }
  }

  // Close modal on Escape key
  handleKeydown(event) {
    if (event.key === "Escape" && !this.modalTarget.classList.contains("hidden")) {
      this.hide(event)
    }
  }

  createModal() {
    // Add event listener for Escape key
    this.boundHandleKeydown = this.handleKeydown.bind(this)
    document.addEventListener("keydown", this.boundHandleKeydown)
  }

  removeModal() {
    // Remove event listener
    if (this.boundHandleKeydown) {
      document.removeEventListener("keydown", this.boundHandleKeydown)
    }
  }
}
