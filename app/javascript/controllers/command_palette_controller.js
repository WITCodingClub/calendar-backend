import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["modal", "input", "results", "item", "noResults", "recentsSection", "recentsContainer", "allItemsSection", "publicIdSection", "publicIdContainer"]

  connect() {
    this.boundKeydown = this.keydown.bind(this)
    this.selectedIndex = 0
    this.recentItems = this.loadRecentItems()
    this.publicIdLookupDebounce = null
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
    if (event.key === "Escape" && !this.modalTarget.classList.contains("hidden")) {
      event.preventDefault()
      this.close()
    }
  }

  open() {
    this.modalTarget.classList.remove("hidden")
    this.inputTarget.focus()
    this.inputTarget.value = ""
    this.selectedIndex = 0
    this.showRecents()
  }

  close() {
    this.modalTarget.classList.add("hidden")
    this.inputTarget.blur()
  }

  showRecents() {
    this.hidePublicIdSection()

    if (this.recentItems.length > 0) {
      this.renderRecents()
      this.recentsSectionTarget.classList.remove("hidden")
    } else {
      this.recentsSectionTarget.classList.add("hidden")
    }

    // Always show all items too
    this.allItemsSectionTarget.classList.remove("hidden")
    this.itemTargets.forEach(item => item.classList.remove("hidden"))
    this.noResultsTarget.classList.add("hidden")
    this.updateSelection()
  }

  showAllItems() {
    this.recentsSectionTarget.classList.add("hidden")
    this.allItemsSectionTarget.classList.remove("hidden")
    this.itemTargets.forEach(item => item.classList.remove("hidden"))
    this.noResultsTarget.classList.add("hidden")
    this.updateSelection()
  }

  renderRecents() {
    // Clear container safely
    while (this.recentsContainerTarget.firstChild) {
      this.recentsContainerTarget.removeChild(this.recentsContainerTarget.firstChild)
    }

    this.recentItems.slice(0, 5).forEach(recent => {
      const template = this.itemTargets.find(item =>
        item.dataset.itemPath === recent.path
      )

      if (template) {
        const clone = template.cloneNode(true)
        clone.dataset.commandPaletteTarget = "item recentItem"
        this.recentsContainerTarget.appendChild(clone)
      }
    })
  }

  filter(event) {
    const query = event.target.value.toLowerCase().trim()

    if (query === "") {
      this.showRecents()
      return
    }

    // Hide recents when searching
    this.recentsSectionTarget.classList.add("hidden")
    this.allItemsSectionTarget.classList.remove("hidden")

    // Check if query looks like a public_id (prefix_hash format)
    const publicIdPattern = /^[a-z]{3}_[a-z0-9]+$/i
    if (publicIdPattern.test(query)) {
      this.lookupPublicId(query)
    } else {
      this.hidePublicIdSection()
    }

    let visibleCount = 0

    this.itemTargets.forEach(item => {
      const searchData = JSON.parse(item.dataset.searchData || '{}')
      const score = this.fuzzyMatch(query, searchData)

      if (score > 0) {
        item.classList.remove("hidden")
        item.dataset.score = score
        visibleCount++
      } else {
        item.classList.add("hidden")
      }
    })

    // Sort by score
    const sortedItems = Array.from(this.itemTargets)
      .filter(item => !item.classList.contains("hidden"))
      .sort((a, b) => parseFloat(b.dataset.score || 0) - parseFloat(a.dataset.score || 0))

    sortedItems.forEach(item => {
      item.parentNode.appendChild(item)
    })

    // Show/hide no results
    if (visibleCount === 0) {
      this.noResultsTarget.classList.remove("hidden")
    } else {
      this.noResultsTarget.classList.add("hidden")
    }

    // Reset selection
    this.selectedIndex = 0
    this.updateSelection()
  }

  fuzzyMatch(query, searchData) {
    const { title = "", description = "", keywords = "", category = "" } = searchData
    const searchText = `${title} ${description} ${keywords} ${category}`.toLowerCase()

    // Exact match gets highest score
    if (searchText.includes(query)) {
      return 100
    }

    // Fuzzy match - check if all characters appear in order
    let score = 0
    let lastIndex = -1

    for (const char of query) {
      const index = searchText.indexOf(char, lastIndex + 1)
      if (index === -1) {
        return 0 // Character not found
      }
      score += (100 - (index - lastIndex)) // Closer together = higher score
      lastIndex = index
    }

    return score
  }

  navigate(event) {
    const visibleItems = this.getVisibleItems()

    if (event.key === "ArrowDown") {
      event.preventDefault()
      this.selectedIndex = Math.min(this.selectedIndex + 1, visibleItems.length - 1)
      this.updateSelection()
    } else if (event.key === "ArrowUp") {
      event.preventDefault()
      this.selectedIndex = Math.max(this.selectedIndex - 1, 0)
      this.updateSelection()
    } else if (event.key === "Enter") {
      event.preventDefault()
      const selected = visibleItems[this.selectedIndex]
      if (selected) {
        this.navigateToItem(selected)
      }
    }
  }

  getVisibleItems() {
    // Priority order: Public ID result > Recents > All items
    if (this.hasPublicIdSectionTarget && !this.publicIdSectionTarget.classList.contains("hidden")) {
      return Array.from(this.publicIdContainerTarget.querySelectorAll('[data-command-palette-target~="item"]'))
    } else if (!this.recentsSectionTarget.classList.contains("hidden")) {
      return Array.from(this.recentsContainerTarget.querySelectorAll('[data-command-palette-target~="item"]'))
    } else {
      return this.itemTargets.filter(item => !item.classList.contains("hidden"))
    }
  }

  updateSelection() {
    const visibleItems = this.getVisibleItems()

    // Remove all selections
    this.itemTargets.forEach(item => {
      item.classList.remove("bg-red-50", "border-l-red-700")
      item.classList.add("border-l-transparent")
    })

    // Also remove from recent items
    this.recentsContainerTarget.querySelectorAll('[data-command-palette-target~="item"]').forEach(item => {
      item.classList.remove("bg-red-50", "border-l-red-700")
      item.classList.add("border-l-transparent")
    })

    // Also remove from public ID items
    if (this.hasPublicIdContainerTarget) {
      this.publicIdContainerTarget.querySelectorAll('[data-command-palette-target~="item"]').forEach(item => {
        item.classList.remove("bg-red-50", "border-l-red-700")
        item.classList.add("border-l-transparent")
      })
    }

    // Add current selection
    if (this.selectedIndex >= 0 && visibleItems[this.selectedIndex]) {
      const selectedItem = visibleItems[this.selectedIndex]
      selectedItem.classList.add("bg-red-50", "border-l-red-700")
      selectedItem.classList.remove("border-l-transparent")

      // Scroll into view
      selectedItem.scrollIntoView({ block: "nearest", behavior: "smooth" })
    }
  }

  selectItem(event) {
    const item = event.currentTarget
    this.navigateToItem(item)
  }

  navigateToItem(item) {
    const path = item.dataset.itemPath
    const title = item.dataset.itemTitle

    if (path) {
      // Save to recents
      this.addToRecents({ path, title })

      // Navigate
      window.location.href = path
    }
  }

  loadRecentItems() {
    try {
      const stored = localStorage.getItem("commandPaletteRecents")
      return stored ? JSON.parse(stored) : []
    } catch {
      return []
    }
  }

  addToRecents(item) {
    // Remove if already exists
    this.recentItems = this.recentItems.filter(r => r.path !== item.path)

    // Add to front
    this.recentItems.unshift(item)

    // Keep only 10 most recent
    this.recentItems = this.recentItems.slice(0, 10)

    // Save to localStorage
    try {
      localStorage.setItem("commandPaletteRecents", JSON.stringify(this.recentItems))
    } catch {
      // Ignore storage errors
    }
  }

  closeOnBackdrop(event) {
    if (event.target === event.currentTarget) {
      this.close()
    }
  }

  stopPropagation(event) {
    event.stopPropagation()
  }

  lookupPublicId(publicId) {
    // Debounce the lookup
    clearTimeout(this.publicIdLookupDebounce)

    this.publicIdLookupDebounce = setTimeout(async () => {
      try {
        const response = await fetch(`/admin/lookup/${encodeURIComponent(publicId)}`)

        if (response.ok) {
          const data = await response.json()
          this.showPublicIdResult(data)
        } else {
          this.hidePublicIdSection()
        }
      } catch (error) {
        console.error("Public ID lookup failed:", error)
        this.hidePublicIdSection()
      }
    }, 300)
  }

  showPublicIdResult(data) {
    if (!this.hasPublicIdSectionTarget) return

    // Clear container
    while (this.publicIdContainerTarget.firstChild) {
      this.publicIdContainerTarget.removeChild(this.publicIdContainerTarget.firstChild)
    }

    // Create result item
    const item = document.createElement('div')
    item.dataset.commandPaletteTarget = "item publicIdItem"
    item.dataset.itemPath = data.path
    item.dataset.itemTitle = data.display_name
    item.className = "flex items-center gap-3 px-3 py-2 cursor-pointer hover:bg-red-50 border-l-4 border-l-transparent transition-colors"

    const icon = document.createElement('span')
    icon.className = "text-2xl"
    icon.textContent = this.getIconForType(data.type)

    const content = document.createElement('div')
    content.className = "flex-1"

    const title = document.createElement('div')
    title.className = "font-medium text-gray-900"
    title.textContent = data.display_name

    const subtitle = document.createElement('div')
    subtitle.className = "text-sm text-gray-500"
    subtitle.textContent = `${data.type} • ${data.public_id}`

    content.appendChild(title)
    content.appendChild(subtitle)

    item.appendChild(icon)
    item.appendChild(content)

    item.addEventListener('click', () => this.navigateToItem(item))

    this.publicIdContainerTarget.appendChild(item)
    this.publicIdSectionTarget.classList.remove("hidden")
  }

  hidePublicIdSection() {
    if (this.hasPublicIdSectionTarget) {
      this.publicIdSectionTarget.classList.add("hidden")
    }
  }

  getIconForType(type) {
    const icons = {
      'Building': '🏢',
      'Room': '🚪',
      'Term': '📅',
      'Course': '📚',
      'Faculty': '👨‍🏫',
      'User': '👤'
    }
    return icons[type] || '📄'
  }
}
