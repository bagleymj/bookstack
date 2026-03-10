import { Controller } from "@hotwired/stimulus"

// Dropdown for adding books to reading list
export default class extends Controller {
  static targets = ["dropdown"]

  toggle() {
    this.dropdownTarget.classList.toggle("hidden")
  }

  close(event) {
    if (!this.element.contains(event.target)) {
      this.dropdownTarget.classList.add("hidden")
    }
  }

  connect() {
    this.closeHandler = this.close.bind(this)
    document.addEventListener("click", this.closeHandler)
  }

  disconnect() {
    document.removeEventListener("click", this.closeHandler)
  }

  async addBook(event) {
    const bookId = event.currentTarget.dataset.bookId
    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content

    try {
      const response = await fetch("/api/v1/reading_list", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": csrfToken,
          "Accept": "application/json"
        },
        credentials: "same-origin",
        body: JSON.stringify({ book_id: bookId })
      })

      if (response.ok) {
        document.dispatchEvent(new CustomEvent("pipeline:refresh"))
        window.location.reload()
      } else {
        const data = await response.json()
        alert(data.errors?.join(", ") || "Failed to add book")
      }
    } catch (error) {
      console.error("Error adding book:", error)
    }
  }
}
