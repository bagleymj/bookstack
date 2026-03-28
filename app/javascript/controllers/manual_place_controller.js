import { Controller } from "@hotwired/stimulus"

// Modal for manually placing a book at a specific Monday + tier
export default class extends Controller {
  static targets = ["modal", "bookTitle", "startDate", "tier", "submitButton", "warnings"]

  connect() {
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

  open(event) {
    event.preventDefault()
    const btn = event.currentTarget
    this.bookId = btn.dataset.bookId
    this.bookTitleTarget.textContent = btn.dataset.bookTitle

    // Default to next Monday
    const today = new Date()
    const dayOfWeek = today.getDay()
    const daysUntilMonday = dayOfWeek === 0 ? 1 : dayOfWeek === 1 ? 0 : 8 - dayOfWeek
    const nextMonday = new Date(today)
    nextMonday.setDate(today.getDate() + daysUntilMonday)
    this.startDateTarget.value = this.formatDate(nextMonday)

    this.tierTarget.value = "two_weeks"
    this.warningsTarget.innerHTML = ""
    this.warningsTarget.classList.add("hidden")
    this.submitButtonTarget.disabled = false

    this.modalTarget.classList.remove("hidden")
    document.body.style.overflow = "hidden"
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

  async submit(event) {
    event.preventDefault()

    const startDate = this.startDateTarget.value
    const tier = this.tierTarget.value

    // Validate Monday
    const date = new Date(startDate + "T00:00:00")
    if (date.getDay() !== 1) {
      this.showWarnings(["Start date must be a Monday"])
      return
    }

    this.submitButtonTarget.disabled = true
    this.submitButtonTarget.textContent = "Placing..."

    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content

    try {
      const response = await fetch("/api/v1/reading_list/manual_place", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": csrfToken,
          "Accept": "application/json"
        },
        credentials: "same-origin",
        body: JSON.stringify({
          book_id: this.bookId,
          start_date: startDate,
          tier: tier
        })
      })

      if (response.ok) {
        const data = await response.json()
        if (data.warnings && data.warnings.length > 0) {
          this.showWarnings(data.warnings)
          // Still reload after a brief pause to show warnings
          setTimeout(() => window.location.reload(), 2000)
        } else {
          window.location.reload()
        }
      } else {
        const data = await response.json()
        this.showWarnings(data.errors || ["Failed to place book"])
        this.submitButtonTarget.disabled = false
        this.submitButtonTarget.textContent = "Place on Schedule"
      }
    } catch (error) {
      this.showWarnings(["Network error — please try again"])
      this.submitButtonTarget.disabled = false
      this.submitButtonTarget.textContent = "Place on Schedule"
    }
  }

  showWarnings(messages) {
    this.warningsTarget.innerHTML = messages.map(m =>
      `<p class="text-sm text-amber-700">${this.escapeHtml(m)}</p>`
    ).join("")
    this.warningsTarget.classList.remove("hidden")
  }

  formatDate(date) {
    const y = date.getFullYear()
    const m = String(date.getMonth() + 1).padStart(2, "0")
    const d = String(date.getDate()).padStart(2, "0")
    return `${y}-${m}-${d}`
  }

  escapeHtml(text) {
    const div = document.createElement("div")
    div.textContent = text
    return div.innerHTML
  }
}
