import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["modal", "bookList"]

  connect() {
    // Close modal on escape key
    this.boundKeydown = this.handleKeydown.bind(this)
    document.addEventListener("keydown", this.boundKeydown)
  }

  disconnect() {
    document.removeEventListener("keydown", this.boundKeydown)
  }

  handleKeydown(event) {
    if (event.key === "Escape" && this.isOpen) {
      this.close()
    }
  }

  get isOpen() {
    return !this.modalTarget.classList.contains("hidden")
  }

  async open(event) {
    event.preventDefault()

    // Show modal
    this.modalTarget.classList.remove("hidden")
    document.body.style.overflow = "hidden"

    // Load active books
    await this.loadBooks()
  }

  close() {
    this.modalTarget.classList.add("hidden")
    document.body.style.overflow = ""
  }

  closeOnBackdrop(event) {
    if (event.target === this.modalTarget) {
      this.close()
    }
  }

  async loadBooks() {
    this.bookListTarget.innerHTML = `
      <div class="flex justify-center py-8">
        <svg class="animate-spin h-8 w-8 text-indigo-600" fill="none" viewBox="0 0 24 24">
          <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
          <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
        </svg>
      </div>
    `

    try {
      const response = await fetch("/api/v1/active_books", {
        headers: {
          "Accept": "application/json",
          "X-Requested-With": "XMLHttpRequest"
        },
        credentials: "same-origin"
      })

      if (!response.ok) throw new Error("Failed to load books")

      const books = await response.json()
      this.renderBooks(books)
    } catch (error) {
      this.bookListTarget.innerHTML = `
        <div class="text-center py-8 text-gray-500">
          <p>Unable to load books</p>
        </div>
      `
    }
  }

  renderBooks(books) {
    if (books.length === 0) {
      this.bookListTarget.innerHTML = `
        <div class="text-center py-8">
          <p class="text-gray-500 mb-4">No books currently being read</p>
          <a href="/books" class="text-indigo-600 font-medium">Browse your library</a>
        </div>
      `
      return
    }

    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content || ""

    const html = books.map(book => `
      <form method="post" action="/books/${book.id}/reading_sessions/start"
            class="flex items-center gap-4 p-4 rounded-lg hover:bg-gray-50 active:bg-gray-100 transition-colors cursor-pointer"
            data-action="click->quick-start#submitForm">
        <input type="hidden" name="authenticity_token" value="${csrfToken}">
        <div class="flex-shrink-0 w-12 h-12 bg-indigo-100 rounded-lg flex items-center justify-center">
          <svg class="w-6 h-6 text-indigo-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 6.253v13m0-13C10.832 5.477 9.246 5 7.5 5S4.168 5.477 3 6.253v13C4.168 18.477 5.754 18 7.5 18s3.332.477 4.5 1.253m0-13C13.168 5.477 14.754 5 16.5 5c1.747 0 3.332.477 4.5 1.253v13C19.832 18.477 18.247 18 16.5 18c-1.746 0-3.332.477-4.5 1.253"/>
          </svg>
        </div>
        <div class="flex-1 min-w-0">
          <p class="font-medium text-gray-900 truncate">${this.escapeHtml(book.title)}</p>
          <p class="text-sm text-gray-500">${book.progress}% complete &bull; p. ${book.current_page}</p>
        </div>
        <div class="flex-shrink-0">
          <svg class="w-5 h-5 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7"/>
          </svg>
        </div>
      </form>
    `).join("")

    this.bookListTarget.innerHTML = html
  }

  submitForm(event) {
    event.preventDefault()
    event.currentTarget.submit()
  }

  escapeHtml(text) {
    const div = document.createElement("div")
    div.textContent = text
    return div.innerHTML
  }
}
