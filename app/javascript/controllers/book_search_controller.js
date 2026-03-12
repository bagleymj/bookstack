import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "results", "loading", "form", "editToggle", "editSearch"]
  static values = {
    url: String,
    editionsUrl: String,
    amazonTag: String,
    mode: { type: String, default: "new" }
  }

  connect() {
    this.debounceTimer = null
    this.abortController = null
    this.lastResults = []
    this.viewMode = "works"       // "works" or "editions"
    this.selectedWork = null       // the work object when viewing editions
    this.editionsCache = new Map() // work_key -> editions array
    this.allEditions = []          // unfiltered editions for current work
    this.editionFilter = ""        // text filter for editions
    this.editionFormatFilter = null // format chip filter (null = all)
    this.searchType = "all"        // search type: "all", "title", "author", "isbn"

    // Close results on click outside
    this.boundClickOutside = this.handleClickOutside.bind(this)
    document.addEventListener("click", this.boundClickOutside)

    // Keyboard navigation
    this.boundKeydown = this.handleKeydown.bind(this)
    if (this.hasInputTarget) {
      this.inputTarget.addEventListener("keydown", this.boundKeydown)
    }

    this.selectedIndex = -1
  }

  disconnect() {
    document.removeEventListener("click", this.boundClickOutside)
    if (this.hasInputTarget) {
      this.inputTarget.removeEventListener("keydown", this.boundKeydown)
    }
    if (this.debounceTimer) clearTimeout(this.debounceTimer)
    if (this.abortController) this.abortController.abort()
  }

  // --- Edit mode toggle ---

  showEditSearch() {
    if (this.hasEditToggleTarget) this.editToggleTarget.classList.add("hidden")

    // Construct a work key from current title+author and jump to editions
    const title = document.getElementById("book_title")?.value || ""
    const author = document.getElementById("book_author")?.value || ""
    if (title) {
      if (this.hasEditSearchTarget) this.editSearchTarget.classList.remove("hidden")
      const work = {
        key: `${title}|||${author}`,
        title: title,
        author: author
      }
      this.showEditionsForWork(work)
      return
    }

    // No title — show the full search bar
    if (this.hasEditSearchTarget) this.editSearchTarget.classList.remove("hidden")
    if (this.hasInputTarget) {
      this.inputTarget.removeEventListener("keydown", this.boundKeydown)
      this.inputTarget.addEventListener("keydown", this.boundKeydown)
      this.inputTarget.focus()
    }
  }

  hideEditSearch() {
    if (this.hasEditSearchTarget) this.editSearchTarget.classList.add("hidden")
    if (this.hasEditToggleTarget) this.editToggleTarget.classList.remove("hidden")
    this.hideResults()
    if (this.hasInputTarget) this.inputTarget.value = ""
  }

  // --- Click outside / keyboard ---

  handleClickOutside(event) {
    if (!this.element.contains(event.target)) {
      this.hideResults()
    }
  }

  handleKeydown(event) {
    const results = this.resultsTarget.querySelectorAll("[data-book-result]")

    switch (event.key) {
      case "ArrowDown":
        event.preventDefault()
        this.selectedIndex = Math.min(this.selectedIndex + 1, results.length - 1)
        this.highlightResult(results)
        break
      case "ArrowUp":
        event.preventDefault()
        this.selectedIndex = Math.max(this.selectedIndex - 1, 0)
        this.highlightResult(results)
        break
      case "Enter":
        event.preventDefault()
        if (this.selectedIndex >= 0 && results[this.selectedIndex]) {
          results[this.selectedIndex].click()
        }
        break
      case "Escape":
        if (this.viewMode === "editions") {
          this.showWorksView()
        } else if (this.modeValue === "edit") {
          this.hideEditSearch()
        } else {
          this.hideResults()
          this.inputTarget.blur()
        }
        break
    }
  }

  highlightResult(results) {
    results.forEach((el, i) => {
      if (i === this.selectedIndex) {
        el.classList.add("bg-indigo-50")
        el.scrollIntoView({ block: "nearest" })
      } else {
        el.classList.remove("bg-indigo-50")
      }
    })
  }

  // --- Step 1: Search works ---

  search() {
    const query = this.inputTarget.value.trim()

    if (this.debounceTimer) clearTimeout(this.debounceTimer)

    if (query.length < 2) {
      this.hideResults()
      return
    }

    this.debounceTimer = setTimeout(() => {
      this.viewMode = "works"
      this.selectedWork = null
      this.performSearch(query)
    }, 300)
  }

  async performSearch(query) {
    if (this.abortController) this.abortController.abort()
    this.abortController = new AbortController()

    this.showLoading("Searching...")

    try {
      const searchTypeParam = this.searchType !== "all" ? `&search_type=${this.searchType}` : ""
      const response = await fetch(`${this.urlValue}?q=${encodeURIComponent(query)}${searchTypeParam}`, {
        headers: { "Accept": "application/json", "X-Requested-With": "XMLHttpRequest" },
        credentials: "same-origin",
        signal: this.abortController.signal
      })

      if (!response.ok) throw new Error("Search failed")

      const data = await response.json()
      this.lastResults = data.results
      this.renderWorksResults(data.results)
    } catch (error) {
      if (error.name === "AbortError") return
      console.error("Book search error:", error)
      this.renderError("Search failed. Please try again.")
    }
  }

  renderSearchTypeTabs() {
    const types = [
      { key: "all", label: "All" },
      { key: "title", label: "Title" },
      { key: "author", label: "Author" },
      { key: "isbn", label: "ISBN" }
    ]
    return `
      <div class="flex gap-1 px-3 py-2 border-b border-gray-100">
        ${types.map(t => {
          const active = this.searchType === t.key
          const classes = active
            ? "bg-indigo-100 text-indigo-700"
            : "bg-gray-100 text-gray-600 hover:bg-gray-200"
          return `<button type="button" data-search-type="${t.key}" class="px-2.5 py-1 text-xs font-medium rounded-full transition-colors ${classes}">${t.label}</button>`
        }).join("")}
      </div>
    `
  }

  bindSearchTypeTabs() {
    this.resultsTarget.querySelectorAll("[data-search-type]").forEach(btn => {
      btn.addEventListener("click", (e) => {
        e.preventDefault()
        e.stopPropagation()
        this.searchType = btn.dataset.searchType
        const query = this.inputTarget.value.trim()
        if (query.length >= 2) {
          this.performSearch(query)
        }
      })
    })
  }

  renderWorksResults(works) {
    this.selectedIndex = -1
    this.viewMode = "works"

    const tabsHtml = this.renderSearchTypeTabs()

    if (works.length === 0) {
      this.resultsTarget.innerHTML = `
        ${tabsHtml}
        <div class="p-4 text-center text-gray-500">
          <p>No books found</p>
          <p class="text-sm mt-1">Try a different search term</p>
        </div>
      `
      this.resultsTarget.classList.remove("hidden")
      this.bindSearchTypeTabs()
      return
    }

    const worksHtml = works.map(work => `
      <button type="button"
              data-book-result
              data-work-key="${this.escapeAttr(work.key || "")}"
              class="w-full flex items-center gap-3 p-3 text-left hover:bg-indigo-50 transition-colors border-b border-gray-100 last:border-0">
        ${work.cover_url
          ? `<img src="${this.escapeAttr(work.cover_url)}" alt="" class="w-10 h-14 object-cover rounded shadow-sm flex-shrink-0" onerror="this.parentElement.replaceChild(this.parentElement.querySelector('.fallback-icon') || this, this)">`
          : ""
        }
        ${!work.cover_url ? `<div class="w-10 h-14 bg-gray-100 rounded flex items-center justify-center flex-shrink-0">
               <svg class="w-5 h-5 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                 <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 6.253v13m0-13C10.832 5.477 9.246 5 7.5 5S4.168 5.477 3 6.253v13C4.168 18.477 5.754 18 7.5 18s3.332.477 4.5 1.253m0-13C13.168 5.477 14.754 5 16.5 5c1.747 0 3.332.477 4.5 1.253v13C19.832 18.477 18.247 18 16.5 18c-1.746 0-3.332.477-4.5 1.253"/>
               </svg>
             </div>` : ""}
        <div class="flex-1 min-w-0">
          <p class="font-medium text-gray-900 truncate">${this.escapeHtml(work.title)}</p>
          <p class="text-sm text-gray-500 truncate">
            ${work.author ? this.escapeHtml(work.author) : "Unknown author"}
            ${work.first_publish_year ? `<span class="text-gray-400">(${work.first_publish_year})</span>` : ""}
          </p>
          <p class="text-xs text-gray-400">
            ${work.edition_count} edition${work.edition_count === 1 ? "" : "s"}
          </p>
        </div>
        <svg class="w-5 h-5 text-gray-400 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7"/>
        </svg>
      </button>
    `).join("")

    this.resultsTarget.innerHTML = tabsHtml + worksHtml
    this.resultsTarget.classList.remove("hidden")
    this.bindSearchTypeTabs()

    // Bind click handlers for works
    this.resultsTarget.querySelectorAll("[data-book-result]").forEach(btn => {
      btn.addEventListener("click", (e) => {
        e.preventDefault()
        e.stopPropagation()
        const workKey = btn.dataset.workKey
        const work = works.find(w => w.key === workKey)
        if (work) this.showEditionsForWork(work)
      })
    })
  }

  // --- Step 2: Fetch and show editions ---

  async showEditionsForWork(work) {
    this.selectedWork = work
    this.viewMode = "editions"
    this.editionFilter = ""
    this.editionFormatFilter = null

    // Check cache first
    if (this.editionsCache.has(work.key)) {
      this.allEditions = this.editionsCache.get(work.key)
      this.renderEditionsResults()
      return
    }

    if (this.abortController) this.abortController.abort()
    this.abortController = new AbortController()

    this.showEditionsLoading(work)

    try {
      let editionsUrl = `${this.editionsUrlValue}?work_key=${encodeURIComponent(work.key)}`
      if (work.volume_ids && work.volume_ids.length > 0) {
        const idsParam = work.volume_ids.map(id => `volume_ids[]=${encodeURIComponent(id)}`).join("&")
        editionsUrl += `&${idsParam}`
      }
      const response = await fetch(editionsUrl, {
        headers: { "Accept": "application/json", "X-Requested-With": "XMLHttpRequest" },
        credentials: "same-origin",
        signal: this.abortController.signal
      })

      if (!response.ok) throw new Error("Failed to load editions")

      const data = await response.json()
      this.editionsCache.set(work.key, data.editions)
      this.allEditions = data.editions
      this.renderEditionsResults()
    } catch (error) {
      if (error.name === "AbortError") return
      console.error("Editions fetch error:", error)
      this.renderEditionsError()
    }
  }

  showEditionsLoading(work) {
    this.resultsTarget.innerHTML = `
      ${this.renderEditionsHeader(work, false)}
      <div class="p-4 flex items-center justify-center text-gray-500">
        <svg class="animate-spin h-5 w-5 mr-2" fill="none" viewBox="0 0 24 24">
          <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
          <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
        </svg>
        Loading editions...
      </div>
    `
    this.resultsTarget.classList.remove("hidden")
    this.bindEditionsHeaderControls()
  }

  renderEditionsHeader(work, showFilter = true) {
    // Collect unique formats from loaded editions for chips
    const formats = showFilter ? this.getAvailableFormats() : []
    const formatChips = formats.map(fmt => {
      const active = this.editionFormatFilter === fmt
      const baseClasses = "px-2 py-0.5 text-xs font-medium rounded-full border transition-colors cursor-pointer whitespace-nowrap"
      const colorClasses = active
        ? "bg-indigo-100 text-indigo-700 border-indigo-300"
        : "bg-white text-gray-600 border-gray-200 hover:bg-gray-50 hover:border-gray-300"
      return `<button type="button" data-format-chip="${this.escapeAttr(fmt)}" class="${baseClasses} ${colorClasses}">${this.escapeHtml(fmt)}</button>`
    }).join("")

    return `
      <div class="sticky top-0 z-10 bg-gray-50 border-b border-gray-200 rounded-t-lg">
        <div class="flex items-center gap-2 px-3 py-2">
          <button type="button" data-back-btn class="p-1 rounded hover:bg-gray-200 transition-colors flex-shrink-0">
            <svg class="w-4 h-4 text-gray-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 19l-7-7 7-7"/>
            </svg>
          </button>
          <div class="flex-1 min-w-0">
            <p class="text-sm font-medium text-gray-900 truncate">${this.escapeHtml(work.title)}</p>
            <p class="text-xs text-gray-500 truncate">${work.author ? this.escapeHtml(work.author) : "Unknown author"}</p>
          </div>
        </div>
        ${showFilter ? `
          <div class="px-3 pb-2 flex items-center gap-2">
            <div class="relative flex-1">
              <svg class="absolute left-2 top-1/2 -translate-y-1/2 w-3.5 h-3.5 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z"/>
              </svg>
              <input type="text"
                     data-edition-filter-input
                     value="${this.escapeAttr(this.editionFilter)}"
                     class="w-full pl-7 pr-2 py-1 text-xs border border-gray-200 rounded-md focus:border-indigo-400 focus:ring-1 focus:ring-indigo-400 focus:outline-none"
                     placeholder="Filter by publisher, year, ISBN...">
            </div>
            ${formats.length > 0 ? `<div class="flex gap-1 flex-shrink-0">${formatChips}</div>` : ""}
          </div>
        ` : ""}
      </div>
    `
  }

  getAvailableFormats() {
    const formatCounts = new Map()
    for (const ed of this.allEditions) {
      if (ed.format) {
        formatCounts.set(ed.format, (formatCounts.get(ed.format) || 0) + 1)
      }
    }
    // Only show formats that appear more than once, sorted by count descending
    return [...formatCounts.entries()]
      .filter(([, count]) => count > 1)
      .sort((a, b) => b[1] - a[1])
      .map(([fmt]) => fmt)
  }

  filterEditions() {
    const query = this.editionFilter.toLowerCase()
    return this.allEditions.filter(edition => {
      // Format chip filter
      if (this.editionFormatFilter && edition.format !== this.editionFormatFilter) {
        return false
      }
      // Text filter — match against publisher, year, isbn, title, format
      if (query) {
        const searchable = [
          edition.publisher, edition.year, edition.isbn,
          edition.title, edition.format
        ].filter(Boolean).join(" ").toLowerCase()
        if (!searchable.includes(query)) return false
      }
      return true
    })
  }

  renderEditionsResults() {
    this.selectedIndex = -1
    const work = this.selectedWork
    const filtered = this.filterEditions()

    if (this.allEditions.length === 0) {
      this.resultsTarget.innerHTML = `
        ${this.renderEditionsHeader(work, false)}
        <div class="p-4 text-center text-gray-500">
          <p>No editions found</p>
          <p class="text-xs mt-1">Try entering the details manually below</p>
        </div>
      `
      this.resultsTarget.classList.remove("hidden")
      this.bindEditionsHeaderControls()
      return
    }

    const amazonTag = this.amazonTagValue
    let editionsHtml
    if (filtered.length === 0) {
      editionsHtml = `
        <div class="p-4 text-center text-gray-500">
          <p>No editions match your filter</p>
          <p class="text-xs mt-1">Try a different search or clear the filter</p>
        </div>
      `
    } else {
      editionsHtml = filtered.map(edition => {
        const dimmed = !edition.pages
        return `
          <button type="button"
                  data-book-result
                  data-edition-key="${this.escapeAttr(edition.key || "")}"
                  class="w-full flex items-center gap-3 p-3 text-left hover:bg-indigo-50 transition-colors border-b border-gray-100 last:border-0${dimmed ? " opacity-50" : ""}${edition.in_collection ? " opacity-60" : ""}">
            ${edition.cover_url
              ? `<img src="${this.escapeAttr(edition.cover_url)}" alt="" class="w-10 h-14 object-cover rounded shadow-sm flex-shrink-0" onerror="this.style.display='none'">`
              : `<div class="w-10 h-14 bg-gray-100 rounded flex items-center justify-center flex-shrink-0">
                   <svg class="w-5 h-5 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                     <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 6.253v13m0-13C10.832 5.477 9.246 5 7.5 5S4.168 5.477 3 6.253v13C4.168 18.477 5.754 18 7.5 18s3.332.477 4.5 1.253m0-13C13.168 5.477 14.754 5 16.5 5c1.747 0 3.332.477 4.5 1.253v13C19.832 18.477 18.247 18 16.5 18c-1.746 0-3.332.477-4.5 1.253"/>
                   </svg>
                 </div>`
            }
            <div class="flex-1 min-w-0">
              <p class="font-medium text-gray-900 truncate">
                ${edition.publisher ? this.escapeHtml(edition.publisher) : this.escapeHtml(edition.title || work.title)}
                ${edition.in_collection ? `<span class="inline-flex items-center ml-1.5 px-1.5 py-0.5 text-xs font-medium rounded bg-green-100 text-green-700">In collection</span>` : ""}
              </p>
              <p class="text-sm text-gray-500 truncate">
                ${edition.year ? edition.year : ""}
                ${edition.format ? `${edition.year ? " · " : ""}${this.escapeHtml(edition.format)}` : ""}
              </p>
              <p class="text-xs text-gray-400">
                ${edition.pages ? `${edition.pages} pages` : `<span class="text-amber-500">pages unknown</span>`}
                ${edition.isbn ? ` · ISBN: ${edition.isbn}` : ""}
              </p>
              ${edition.isbn && amazonTag ? `<a href="https://www.amazon.com/s?k=${encodeURIComponent(edition.isbn)}&tag=${encodeURIComponent(amazonTag)}" target="_blank" rel="noopener" data-amazon-link class="inline-flex items-center gap-1 text-xs text-amber-700 hover:text-amber-900 mt-0.5">Buy on Amazon <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 6H6a2 2 0 00-2 2v10a2 2 0 002 2h10a2 2 0 002-2v-4M14 4h6m0 0v6m0-6L10 14"/></svg></a>` : ""}
            </div>
            <svg class="w-5 h-5 text-gray-400 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4"/>
            </svg>
          </button>
        `
      }).join("")
    }

    // Show count
    const countText = filtered.length === this.allEditions.length
      ? `${this.allEditions.length} editions`
      : `${filtered.length} of ${this.allEditions.length} editions`
    const countHtml = `<div class="px-3 py-1 text-xs text-gray-400 border-b border-gray-100">${countText}</div>`

    this.resultsTarget.innerHTML = this.renderEditionsHeader(work) + countHtml + editionsHtml
    this.resultsTarget.classList.remove("hidden")
    this.bindEditionsHeaderControls()

    // Bind click handlers for editions
    this.resultsTarget.querySelectorAll("[data-book-result]").forEach(btn => {
      btn.addEventListener("click", (e) => {
        e.preventDefault()
        e.stopPropagation()
        const editionKey = btn.dataset.editionKey
        const edition = this.allEditions.find(ed => ed.key === editionKey)
        if (edition) this.selectEdition(edition)
      })
    })

    // Prevent Amazon links from triggering edition selection
    this.resultsTarget.querySelectorAll("[data-amazon-link]").forEach(link => {
      link.addEventListener("click", (e) => e.stopPropagation())
    })

    // Restore focus to filter input if it was active
    const filterInput = this.resultsTarget.querySelector("[data-edition-filter-input]")
    if (filterInput && this.editionFilter) {
      filterInput.focus()
      filterInput.setSelectionRange(filterInput.value.length, filterInput.value.length)
    }
  }

  renderEditionsError() {
    const work = this.selectedWork
    this.resultsTarget.innerHTML = `
      ${this.renderEditionsHeader(work, false)}
      <div class="p-4 text-center text-red-500">
        <p>Failed to load editions. Please try again.</p>
      </div>
    `
    this.bindEditionsHeaderControls()
  }

  bindEditionsHeaderControls() {
    // Back button
    const backBtn = this.resultsTarget.querySelector("[data-back-btn]")
    if (backBtn) {
      backBtn.addEventListener("click", (e) => {
        e.preventDefault()
        e.stopPropagation()
        this.showWorksView()
      })
    }

    // Text filter input
    const filterInput = this.resultsTarget.querySelector("[data-edition-filter-input]")
    if (filterInput) {
      filterInput.addEventListener("input", (e) => {
        e.stopPropagation()
        this.editionFilter = e.target.value
        this.renderEditionsResults()
      })
      // Prevent main search from triggering
      filterInput.addEventListener("keydown", (e) => {
        e.stopPropagation()
        if (e.key === "Escape") {
          if (this.editionFilter) {
            this.editionFilter = ""
            this.renderEditionsResults()
          } else {
            this.showWorksView()
          }
        }
      })
    }

    // Format chips
    this.resultsTarget.querySelectorAll("[data-format-chip]").forEach(chip => {
      chip.addEventListener("click", (e) => {
        e.preventDefault()
        e.stopPropagation()
        const fmt = chip.dataset.formatChip
        // Toggle: click active chip to deactivate
        this.editionFormatFilter = this.editionFormatFilter === fmt ? null : fmt
        this.renderEditionsResults()
      })
    })
  }

  showWorksView() {
    // In edit mode, there's no works list to go back to — just close
    if (this.modeValue === "edit") {
      this.hideEditSearch()
      return
    }

    this.viewMode = "works"
    this.selectedWork = null
    if (this.lastResults.length > 0) {
      this.renderWorksResults(this.lastResults)
    } else {
      this.hideResults()
    }
  }

  // --- Step 3: Select edition and populate form ---

  selectEdition(edition) {
    const work = this.selectedWork

    if (this.modeValue === "edit") {
      // In edit mode, only update edition-specific fields (not title/author)
      this.setFormField("book_isbn", edition.isbn)
      this.setFormField("book_cover_image_url", edition.cover_url || work?.cover_url)
      if (edition.pages) {
        this.setFormField("book_last_page", String(edition.pages))
      }
    } else {
      // In new mode, populate all fields
      this.setFormField("book_title", edition.title || work?.title)
      this.setFormField("book_author", work?.author)
      this.setFormField("book_isbn", edition.isbn)
      this.setFormField("book_cover_image_url", edition.cover_url || work?.cover_url)
      if (edition.pages) {
        this.setFormField("book_last_page", String(edition.pages))
      }
    }

    // Update the page range slider if present
    this.updatePageRangeSlider(edition)

    // Clear search and hide results
    if (this.hasInputTarget) this.inputTarget.value = ""
    this.viewMode = "works"
    this.selectedWork = null
    this.hideResults()

    if (this.modeValue === "edit") {
      // In edit mode, collapse the search back to the button
      this.hideEditSearch()
      this.showConfirmation("Edition updated")
    } else {
      // Focus the first empty required field
      const lastPageField = document.getElementById("book_last_page")
      const titleField = document.getElementById("book_title")
      if (!lastPageField?.value) {
        lastPageField?.focus()
      } else {
        titleField?.focus()
      }
      this.showConfirmation(edition.title || work?.title)
    }
  }

  updatePageRangeSlider(edition) {
    const sliderEl = document.querySelector("[data-controller='page-range-slider']")
    if (!sliderEl) return

    const slider = this.application.getControllerForElementAndIdentifier(sliderEl, "page-range-slider")
    if (!slider) return

    if (edition.pages) {
      slider.maxValue = edition.pages
      slider.currentMinValue = edition.recommended_first_page || 1
      slider.currentMaxValue = edition.recommended_last_page || edition.pages
      slider.recommendedMinValue = edition.recommended_first_page || 0
      slider.recommendedMaxValue = edition.recommended_last_page || 0
      slider.syncToInput("both")
    }
  }

  // --- Shared helpers ---

  showLoading(message) {
    this.resultsTarget.classList.remove("hidden")
    this.resultsTarget.innerHTML = `
      <div class="p-4 flex items-center justify-center text-gray-500">
        <svg class="animate-spin h-5 w-5 mr-2" fill="none" viewBox="0 0 24 24">
          <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
          <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
        </svg>
        ${message}
      </div>
    `
  }

  renderError(message) {
    this.resultsTarget.innerHTML = `
      <div class="p-4 text-center text-red-500">
        <p>${message}</p>
      </div>
    `
    this.resultsTarget.classList.remove("hidden")
  }

  setFormField(id, value) {
    const field = document.getElementById(id)
    if (field && value) {
      field.value = value
      field.dispatchEvent(new Event("change", { bubbles: true }))
    }
  }

  showConfirmation(title) {
    const toast = document.createElement("div")
    toast.className = "fixed bottom-4 right-4 bg-green-600 text-white px-4 py-2 rounded-lg shadow-lg z-50 animate-fade-in"
    toast.innerHTML = `
      <div class="flex items-center gap-2">
        <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"/>
        </svg>
        <span>${this.escapeHtml(title)}</span>
      </div>
    `
    document.body.appendChild(toast)
    setTimeout(() => toast.remove(), 2000)
  }

  hideResults() {
    this.resultsTarget.classList.add("hidden")
    this.selectedIndex = -1
  }

  escapeHtml(text) {
    if (!text) return ""
    const div = document.createElement("div")
    div.textContent = text
    return div.innerHTML
  }

  escapeAttr(text) {
    if (!text) return ""
    return text.replace(/&/g, "&amp;").replace(/"/g, "&quot;").replace(/'/g, "&#39;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
  }
}
