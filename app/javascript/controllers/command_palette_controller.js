import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["modal", "input", "results", "item"]

  connect() {
    this.boundKeydown = this.keydown.bind(this)
    this.selectedIndex = -1
    document.addEventListener("keydown", this.boundKeydown)
  }

  disconnect() {
    document.removeEventListener("keydown", this.boundKeydown)
  }

  keydown(event) {
    // Command/Ctrl + K
    if ((event.metaKey || event.ctrlKey) && event.key === "k") {
      event.preventDefault()
      this.open()
    }
    
    // Escape to close
    if (event.key === "Escape") {
      this.close()
    }
  }

  open() {
    this.modalTarget.classList.remove("hidden")
    this.inputTarget.focus()
    this.inputTarget.value = ""
    this.selectedIndex = -1
    this.showAllItems()
  }

  close() {
    this.modalTarget.classList.add("hidden")
  }

  filter(event) {
    const query = event.target.value.toLowerCase()
    
    this.itemTargets.forEach(item => {
      const text = item.textContent.toLowerCase()
      const shouldShow = text.includes(query)
      
      if (shouldShow) {
        item.classList.remove("hidden")
      } else {
        item.classList.add("hidden")
      }
    })
    
    // Reset selection when filtering
    this.selectedIndex = -1
    const visibleItems = this.itemTargets.filter(item => !item.classList.contains("hidden"))
    this.updateSelection(visibleItems)
  }

  showAllItems() {
    this.itemTargets.forEach(item => {
      item.classList.remove("hidden")
    })
  }

  navigate(event) {
    const visibleItems = this.itemTargets.filter(item => !item.classList.contains("hidden"))
    
    if (event.key === "ArrowDown") {
      event.preventDefault()
      this.selectedIndex = Math.min(this.selectedIndex + 1, visibleItems.length - 1)
      this.updateSelection(visibleItems)
    } else if (event.key === "ArrowUp") {
      event.preventDefault()
      this.selectedIndex = Math.max(this.selectedIndex - 1, 0)
      this.updateSelection(visibleItems)
    } else if (event.key === "Enter") {
      event.preventDefault()
      if (this.selectedIndex >= 0 && visibleItems[this.selectedIndex]) {
        const link = visibleItems[this.selectedIndex].querySelector("a")
        if (link) {
          window.location.href = link.href
        }
      } else if (visibleItems.length > 0) {
        // If no selection, use first item
        const link = visibleItems[0].querySelector("a")
        if (link) {
          window.location.href = link.href
        }
      }
    }
  }

  updateSelection(visibleItems) {
    // Remove previous selection
    this.itemTargets.forEach(item => {
      item.classList.remove("bg-[#d13732]", "text-white")
      item.classList.add("hover:bg-gray-50")
    })

    // Add current selection
    if (this.selectedIndex >= 0 && visibleItems[this.selectedIndex]) {
      const selectedItem = visibleItems[this.selectedIndex]
      selectedItem.classList.add("bg-[#d13732]", "text-white")
      selectedItem.classList.remove("hover:bg-gray-50")
      
      // Update link text color too
      const link = selectedItem.querySelector("a")
      if (link) {
        link.classList.add("text-white")
        link.classList.remove("text-gray-900")
      }
    }
  }

  clickItem(event) {
    // If clicking on the item but not the link, trigger the link
    if (event.target.tagName !== "A") {
      const link = event.currentTarget.querySelector("a")
      if (link) {
        window.location.href = link.href
      }
    }
  }

  closeOnBackdrop(event) {
    // Only close if clicking on the backdrop, not the modal content
    if (event.target === event.currentTarget) {
      this.close()
    }
  }

  stopPropagation(event) {
    event.stopPropagation()
  }
}