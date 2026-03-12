import { Controller } from "@hotwired/stimulus"

// Shows +/-Xm impact indicator next to "Add to reading list" checkbox on the book form.
// Fetches from /api/v1/reading_list/impact_preview when page range or density changes.
export default class extends Controller {
  static targets = ["badge", "checkbox"]
  static values = { url: String }

  connect() {
    this.debounceTimer = null
    this.fetchImpact()
  }

  // Called when first_page, last_page, or density changes
  update() {
    clearTimeout(this.debounceTimer)
    this.debounceTimer = setTimeout(() => this.fetchImpact(), 300)
  }

  // Called when checkbox toggled
  toggle() {
    if (!this.hasCheckboxTarget) return
    if (this.checkboxTarget.checked) {
      this.fetchImpact()
    } else {
      this.hideBadge()
    }
  }

  async fetchImpact() {
    if (this.hasCheckboxTarget && !this.checkboxTarget.checked) {
      this.hideBadge()
      return
    }

    const firstPage = document.getElementById("book_first_page")?.value || "1"
    const lastPage = document.getElementById("book_last_page")?.value || "0"
    const density = document.getElementById("book_density")?.value || "average"

    if (!lastPage || parseInt(lastPage) <= parseInt(firstPage)) {
      this.hideBadge()
      return
    }

    try {
      const url = `${this.urlValue}?first_page=${firstPage}&last_page=${lastPage}&density=${density}`
      const response = await fetch(url, {
        headers: { "Accept": "application/json" },
        credentials: "same-origin"
      })

      if (response.ok) {
        const data = await response.json()
        this.showBadge(data.delta)
      }
    } catch (error) {
      console.error("Impact preview error:", error)
    }
  }

  showBadge(delta) {
    if (!this.hasBadgeTarget) return

    if (delta === 0) {
      this.badgeTarget.textContent = "no change"
      this.badgeTarget.className = "inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium bg-gray-100 text-gray-600 ml-2"
    } else {
      const sign = delta > 0 ? "+" : ""
      this.badgeTarget.textContent = `${sign}${delta}m/day`
      if (delta > 0) {
        this.badgeTarget.className = "inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium bg-amber-100 text-amber-700 ml-2"
      } else {
        this.badgeTarget.className = "inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium bg-green-100 text-green-700 ml-2"
      }
    }
    this.badgeTarget.classList.remove("hidden")
  }

  hideBadge() {
    if (!this.hasBadgeTarget) return
    this.badgeTarget.classList.add("hidden")
  }
}
