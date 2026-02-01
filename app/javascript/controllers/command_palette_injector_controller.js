import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    // Only inject if command palette doesn't already exist
    if (document.querySelector('[data-controller="command-palette"]')) {
      return
    }

    // Fetch navigation data and inject command palette
    this.injectCommandPalette()
  }

  async injectCommandPalette() {
    try {
      const response = await fetch('/admin/navigation')
      if (!response.ok) return

      const data = await response.json()

      // Build command palette DOM
      const modal = this.buildCommandPaletteModal(data.categories)

      // Append to body
      document.body.appendChild(modal)

      // Initialize Stimulus controller
      this.application.getControllerForElementAndIdentifier(modal, "command-palette")
    } catch (error) {
      console.error('Failed to inject command palette:', error)
    }
  }

  buildCommandPaletteModal(categories) {
    // Main container
    const container = document.createElement('div')
    container.setAttribute('data-controller', 'command-palette')
    container.setAttribute('data-command-palette-target', 'modal')
    container.setAttribute('data-action', 'click->command-palette#closeOnBackdrop')
    container.className = 'fixed inset-0 bg-black/60 backdrop-blur-sm flex items-start justify-center pt-[15vh] z-50 hidden'

    // Inner modal
    const innerModal = document.createElement('div')
    innerModal.setAttribute('data-action', 'click->command-palette#stopPropagation')
    innerModal.className = 'bg-white rounded-xl shadow-2xl w-full max-w-2xl mx-4 overflow-hidden border border-gray-200'

    // Search section
    const searchSection = this.buildSearchSection()
    innerModal.appendChild(searchSection)

    // Results section
    const resultsSection = this.buildResultsSection(categories)
    innerModal.appendChild(resultsSection)

    // Footer section
    const footer = this.buildFooter()
    innerModal.appendChild(footer)

    container.appendChild(innerModal)
    return container
  }

  buildSearchSection() {
    const searchDiv = document.createElement('div')
    searchDiv.className = 'relative'

    // Icon container
    const iconContainer = document.createElement('div')
    iconContainer.className = 'absolute inset-y-0 left-0 pl-4 flex items-center pointer-events-none'

    const iconSvg = document.createElementNS('http://www.w3.org/2000/svg', 'svg')
    iconSvg.setAttribute('class', 'w-5 h-5 text-gray-400')
    iconSvg.setAttribute('fill', 'none')
    iconSvg.setAttribute('stroke', 'currentColor')
    iconSvg.setAttribute('viewBox', '0 0 24 24')

    const iconPath = document.createElementNS('http://www.w3.org/2000/svg', 'path')
    iconPath.setAttribute('stroke-linecap', 'round')
    iconPath.setAttribute('stroke-linejoin', 'round')
    iconPath.setAttribute('stroke-width', '2')
    iconPath.setAttribute('d', 'M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z')

    iconSvg.appendChild(iconPath)
    iconContainer.appendChild(iconSvg)

    // Input
    const input = document.createElement('input')
    input.setAttribute('data-command-palette-target', 'input')
    input.setAttribute('data-action', 'input->command-palette#filter keydown->command-palette#navigate')
    input.type = 'text'
    input.placeholder = 'Search or jump to...'
    input.className = 'w-full pl-12 pr-4 py-4 text-base border-0 border-b border-gray-200 focus:outline-none focus:ring-0 focus:border-gray-300'

    searchDiv.appendChild(iconContainer)
    searchDiv.appendChild(input)
    return searchDiv
  }

  buildResultsSection(categories) {
    const resultsDiv = document.createElement('div')
    resultsDiv.setAttribute('data-command-palette-target', 'results')
    resultsDiv.className = 'max-h-96 overflow-y-auto'

    // Recent items section
    const recentsSection = document.createElement('div')
    recentsSection.setAttribute('data-command-palette-target', 'recentsSection')
    recentsSection.className = 'hidden'

    const recentsHeader = document.createElement('div')
    recentsHeader.className = 'px-4 py-2 text-xs font-semibold text-gray-500 uppercase tracking-wider bg-gray-50'
    recentsHeader.textContent = 'Recent'

    const recentsContainer = document.createElement('div')
    recentsContainer.setAttribute('data-command-palette-target', 'recentsContainer')

    recentsSection.appendChild(recentsHeader)
    recentsSection.appendChild(recentsContainer)

    // All items section
    const allItemsSection = document.createElement('div')
    allItemsSection.setAttribute('data-command-palette-target', 'allItemsSection')

    const allItemsHeader = document.createElement('div')
    allItemsHeader.className = 'px-4 py-2 text-xs font-semibold text-gray-500 uppercase tracking-wider bg-gray-50'
    allItemsHeader.textContent = 'All Commands'

    allItemsSection.appendChild(allItemsHeader)

    // Add all category items
    categories.forEach(category => {
      category.items.forEach(item => {
        if (item.path) {
          const itemElement = this.buildItemElement(item, category.title)
          allItemsSection.appendChild(itemElement)
        }
      })
    })

    // No results message
    const noResults = document.createElement('div')
    noResults.setAttribute('data-command-palette-target', 'noResults')
    noResults.className = 'hidden px-4 py-8 text-center text-sm text-gray-500'
    noResults.textContent = 'No results found'

    resultsDiv.appendChild(recentsSection)
    resultsDiv.appendChild(allItemsSection)
    resultsDiv.appendChild(noResults)
    return resultsDiv
  }

  buildItemElement(item, categoryTitle) {
    const itemDiv = document.createElement('div')
    itemDiv.setAttribute('data-command-palette-target', 'item')
    itemDiv.setAttribute('data-item-path', item.path)
    itemDiv.setAttribute('data-item-title', item.title)

    const searchData = JSON.stringify({
      title: item.title,
      description: item.description || '',
      keywords: (item.keywords || []).join(' '),
      category: categoryTitle
    })
    itemDiv.setAttribute('data-search-data', searchData)
    itemDiv.setAttribute('data-action', 'click->command-palette#selectItem')
    itemDiv.className = 'px-4 py-2.5 hover:bg-gray-50 cursor-pointer transition group border-l-2 border-transparent'

    // Content wrapper
    const contentWrapper = document.createElement('div')
    contentWrapper.className = 'flex items-center justify-between gap-3'

    // Left side
    const leftSide = document.createElement('div')
    leftSide.className = 'flex-1 min-w-0'

    const titleRow = document.createElement('div')
    titleRow.className = 'flex items-center gap-2'

    const titleDiv = document.createElement('div')
    titleDiv.className = 'font-medium text-sm text-gray-900 truncate'
    titleDiv.textContent = item.title

    titleRow.appendChild(titleDiv)

    if (item.read_only) {
      const badge = document.createElement('span')
      badge.className = 'inline-flex items-center px-1.5 py-0.5 rounded text-xs font-medium bg-gray-100 text-gray-600'
      badge.textContent = 'Read-only'
      titleRow.appendChild(badge)
    }

    leftSide.appendChild(titleRow)

    if (item.description) {
      const descDiv = document.createElement('div')
      descDiv.className = 'text-xs text-gray-500 truncate mt-0.5'
      descDiv.textContent = item.description
      leftSide.appendChild(descDiv)
    }

    // Right side
    const rightSide = document.createElement('div')
    rightSide.className = 'flex items-center gap-2 flex-shrink-0'

    const categorySpan = document.createElement('span')
    categorySpan.className = 'text-xs text-gray-400 uppercase'
    categorySpan.textContent = categoryTitle

    const arrowSvg = document.createElementNS('http://www.w3.org/2000/svg', 'svg')
    arrowSvg.setAttribute('class', 'w-4 h-4 text-gray-400 opacity-0 group-hover:opacity-100 transition')
    arrowSvg.setAttribute('fill', 'none')
    arrowSvg.setAttribute('stroke', 'currentColor')
    arrowSvg.setAttribute('viewBox', '0 0 24 24')

    const arrowPath = document.createElementNS('http://www.w3.org/2000/svg', 'path')
    arrowPath.setAttribute('stroke-linecap', 'round')
    arrowPath.setAttribute('stroke-linejoin', 'round')
    arrowPath.setAttribute('stroke-width', '2')
    arrowPath.setAttribute('d', 'M9 5l7 7-7 7')

    arrowSvg.appendChild(arrowPath)

    rightSide.appendChild(categorySpan)
    rightSide.appendChild(arrowSvg)

    contentWrapper.appendChild(leftSide)
    contentWrapper.appendChild(rightSide)
    itemDiv.appendChild(contentWrapper)

    return itemDiv
  }

  buildFooter() {
    const footer = document.createElement('div')
    footer.className = 'px-4 py-3 bg-gray-50 border-t border-gray-200'

    const innerDiv = document.createElement('div')
    innerDiv.className = 'flex items-center justify-between text-xs text-gray-500'

    // Left side hints
    const leftHints = document.createElement('div')
    leftHints.className = 'flex items-center gap-3'

    // Navigate hint
    const navHint = document.createElement('div')
    navHint.className = 'flex items-center gap-1'

    const navKbd = document.createElement('kbd')
    navKbd.className = 'px-2 py-1 bg-white border border-gray-300 rounded text-xs font-medium shadow-sm'
    navKbd.textContent = '↑↓'

    const navSpan = document.createElement('span')
    navSpan.textContent = 'Navigate'

    navHint.appendChild(navKbd)
    navHint.appendChild(navSpan)

    // Select hint
    const selectHint = document.createElement('div')
    selectHint.className = 'flex items-center gap-1'

    const selectKbd = document.createElement('kbd')
    selectKbd.className = 'px-2 py-1 bg-white border border-gray-300 rounded text-xs font-medium shadow-sm'
    selectKbd.textContent = '↵'

    const selectSpan = document.createElement('span')
    selectSpan.textContent = 'Select'

    selectHint.appendChild(selectKbd)
    selectHint.appendChild(selectSpan)

    leftHints.appendChild(navHint)
    leftHints.appendChild(selectHint)

    // Right side hint
    const closeHint = document.createElement('div')
    closeHint.className = 'flex items-center gap-1'

    const closeKbd = document.createElement('kbd')
    closeKbd.className = 'px-2 py-1 bg-white border border-gray-300 rounded text-xs font-medium shadow-sm'
    closeKbd.textContent = 'ESC'

    const closeSpan = document.createElement('span')
    closeSpan.textContent = 'Close'

    closeHint.appendChild(closeKbd)
    closeHint.appendChild(closeSpan)

    innerDiv.appendChild(leftHints)
    innerDiv.appendChild(closeHint)
    footer.appendChild(innerDiv)

    return footer
  }
}
