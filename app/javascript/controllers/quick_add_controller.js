import { Controller } from "@hotwired/stimulus"

// Handles one-click adding of a book to the reading list
export default class extends Controller {
  static values = { bookId: Number }
  static targets = ["button"]

  async add(event) {
    event.preventDefault()
    event.stopPropagation()

    const button = this.buttonTarget
    button.disabled = true
    button.classList.add("opacity-50")

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
        document.dispatchEvent(new CustomEvent("pipeline:refresh"))
        window.location.reload()
      } else {
        const data = await response.json()
        button.disabled = false
        button.classList.remove("opacity-50")
        alert(data.errors?.join(", ") || "Failed to add book")
      }
    } catch (error) {
      console.error("Error adding book:", error)
      button.disabled = false
      button.classList.remove("opacity-50")
    }
  }
}
