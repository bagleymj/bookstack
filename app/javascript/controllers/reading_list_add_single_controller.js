import { Controller } from "@hotwired/stimulus"

// Adds a single book to reading list from the book show page
export default class extends Controller {
  static values = { bookId: Number }

  async add() {
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
        body: JSON.stringify({ book_id: this.bookIdValue })
      })

      if (response.ok) {
        window.location.reload()
      } else {
        const data = await response.json()
        alert(data.errors?.join(", ") || "Failed to add book to reading list")
      }
    } catch (error) {
      console.error("Error adding book to reading list:", error)
    }
  }
}
