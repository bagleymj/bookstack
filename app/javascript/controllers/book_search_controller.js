import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "results", "loading", "form"]
  static values = { url: String, amazonTag: String }

  connect() {
    this.debounceTimer = null
    this.abortController = null

    // Close results on click outside
    this.boundClickOutside = this.handleClickOutside.bind(this)
    document.addEventListener("click", this.boundClickOutside)

    // Keyboard navigation
    this.boundKeydown = this.handleKeydown.bind(this)
    this.inputTarget.addEventListener("keydown", this.boundKeydown)

    this.selectedIndex = -1
  }

  disconnect() {
    document.removeEventListener("click", this.boundClickOutside)
    this.inputTarget.removeEventListener("keydown", this.boundKeydown)
    if (this.debounceTimer) clearTimeout(this.debounceTimer)
    if (this.abortController) this.abortController.abort()
  }

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
          this.selectResult({ currentTarget: results[this.selectedIndex] })
        }
        break
      case "Escape":
        this.hideResults()
        this.inputTarget.blur()
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

  search() {
    const query = this.inputTarget.value.trim()

    // Clear previous timer
    if (this.debounceTimer) clearTimeout(this.debounceTimer)

    // Hide results if query is too short
    if (query.length < 2) {
      this.hideResults()
      return
    }

    // Debounce the search (300ms)
    this.debounceTimer = setTimeout(() => {
      this.performSearch(query)
    }, 300)
  }

  async performSearch(query) {
    // Abort previous request
    if (this.abortController) {
      this.abortController.abort()
    }
    this.abortController = new AbortController()

    // Show loading state
    this.showLoading()

    try {
      const response = await fetch(`${this.urlValue}?q=${encodeURIComponent(query)}`, {
        headers: {
          "Accept": "application/json",
          "X-Requested-With": "XMLHttpRequest"
        },
        credentials: "same-origin",
        signal: this.abortController.signal
      })

      if (!response.ok) throw new Error("Search failed")

      const data = await response.json()
      this.renderResults(data.results)
    } catch (error) {
      if (error.name === "AbortError") return // Ignore aborted requests

      console.error("Book search error:", error)
      this.renderError()
    }
  }

  showLoading() {
    this.resultsTarget.classList.remove("hidden")
    this.resultsTarget.innerHTML = `
      <div class="p-4 flex items-center justify-center text-gray-500">
        <svg class="animate-spin h-5 w-5 mr-2" fill="none" viewBox="0 0 24 24">
          <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
          <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
        </svg>
        Searching...
      </div>
    `
  }

  renderResults(results) {
    this.selectedIndex = -1

    if (results.length === 0) {
      this.resultsTarget.innerHTML = `
        <div class="p-4 text-center text-gray-500">
          <p>No books found</p>
          <p class="text-sm mt-1">Try a different search or enter details manually below</p>
        </div>
      `
      return
    }

    const amazonTag = this.amazonTagValue
    const html = results.map((book, index) => `
      <button type="button"
              data-book-result
              data-action="click->book-search#selectResult"
              data-book-title="${this.escapeAttr(book.title || "")}"
              data-book-author="${this.escapeAttr(book.author || "")}"
              data-book-pages="${book.pages || ""}"
              data-book-isbn="${this.escapeAttr(book.isbn || "")}"
              data-book-cover="${this.escapeAttr(book.cover_url || "")}"
              data-book-publisher="${this.escapeAttr(book.publisher || "")}"
              class="w-full flex items-center gap-3 p-3 text-left hover:bg-indigo-50 transition-colors border-b border-gray-100 last:border-0">
        ${book.cover_url_small
          ? `<img src="${this.escapeAttr(book.cover_url_small)}" alt="" class="w-10 h-14 object-cover rounded shadow-sm flex-shrink-0" onerror="this.style.display='none'">`
          : `<div class="w-10 h-14 bg-gray-100 rounded flex items-center justify-center flex-shrink-0">
               <svg class="w-5 h-5 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                 <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 6.253v13m0-13C10.832 5.477 9.246 5 7.5 5S4.168 5.477 3 6.253v13C4.168 18.477 5.754 18 7.5 18s3.332.477 4.5 1.253m0-13C13.168 5.477 14.754 5 16.5 5c1.747 0 3.332.477 4.5 1.253v13C19.832 18.477 18.247 18 16.5 18c-1.746 0-3.332.477-4.5 1.253"/>
               </svg>
             </div>`
        }
        <div class="flex-1 min-w-0">
          <p class="font-medium text-gray-900 truncate">${this.escapeHtml(book.title)}</p>
          <p class="text-sm text-gray-500 truncate">
            ${book.author ? this.escapeHtml(book.author) : "Unknown author"}
            ${book.year ? `<span class="text-gray-400">(${book.year})</span>` : ""}
          </p>
          <p class="text-xs text-gray-400">
            ${book.pages ? `${book.pages} pages` : ""}
            ${book.publisher ? `${book.pages ? " · " : ""}${this.escapeHtml(book.publisher)}` : ""}
            ${book.isbn ? ` · ISBN: ${book.isbn}` : ""}
          </p>
          ${book.isbn && amazonTag ? `<a href="https://www.amazon.com/s?k=${encodeURIComponent(book.isbn)}&tag=${encodeURIComponent(amazonTag)}" target="_blank" rel="noopener" data-action="click->book-search#stopPropagation" class="inline-flex items-center gap-1 text-xs text-amber-700 hover:text-amber-900 mt-0.5">Buy on Amazon <svg class="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 6H6a2 2 0 00-2 2v10a2 2 0 002 2h10a2 2 0 002-2v-4M14 4h6m0 0v6m0-6L10 14"/></svg></a>` : ""}
        </div>
        <svg class="w-5 h-5 text-gray-400 flex-shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4"/>
        </svg>
      </button>
    `).join("")

    this.resultsTarget.innerHTML = html
    this.resultsTarget.classList.remove("hidden")
  }

  renderError() {
    this.resultsTarget.innerHTML = `
      <div class="p-4 text-center text-red-500">
        <p>Search failed. Please try again.</p>
      </div>
    `
  }

  selectResult(event) {
    const button = event.currentTarget
    const data = button.dataset

    // Populate form fields
    this.setFormField("book_title", data.bookTitle)
    this.setFormField("book_author", data.bookAuthor)
    this.setFormField("book_isbn", data.bookIsbn)
    this.setFormField("book_cover_image_url", data.bookCover)

    // Set last_page if pages available (first_page stays at 1)
    if (data.bookPages) {
      this.setFormField("book_last_page", data.bookPages)
    }

    // Clear search and hide results
    this.inputTarget.value = ""
    this.hideResults()

    // Focus the first empty required field
    const titleField = document.getElementById("book_title")
    const lastPageField = document.getElementById("book_last_page")
    if (!lastPageField?.value) {
      lastPageField?.focus()
    } else {
      titleField?.focus()
    }

    // Show a brief confirmation
    this.showConfirmation(data.bookTitle)
  }

  setFormField(id, value) {
    const field = document.getElementById(id)
    if (field && value) {
      field.value = value
      // Trigger change event for any listeners
      field.dispatchEvent(new Event("change", { bubbles: true }))
    }
  }

  showConfirmation(title) {
    // Create a brief toast notification
    const toast = document.createElement("div")
    toast.className = "fixed bottom-4 right-4 bg-green-600 text-white px-4 py-2 rounded-lg shadow-lg z-50 animate-fade-in"
    toast.innerHTML = `
      <div class="flex items-center gap-2">
        <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"/>
        </svg>
        <span>Added: ${this.escapeHtml(title)}</span>
      </div>
    `
    document.body.appendChild(toast)

    setTimeout(() => {
      toast.remove()
    }, 2000)
  }

  stopPropagation(event) {
    event.stopPropagation()
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
    return text.replace(/"/g, "&quot;").replace(/'/g, "&#39;")
  }
}
