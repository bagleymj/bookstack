import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["pagesRemaining", "daysRemaining", "pagesPerDay", "minutesPerDay"]
  static values = {
    firstPage: Number,
    lastPage: Number,
    targetDate: String,
    includeWeekends: Boolean
  }

  connect() {
    this.currentPageInput = document.querySelector('input[name="current_page"]')
    this.startDateInput = document.querySelector('input[name="start_date"]')

    if (this.currentPageInput) {
      this.currentPageInput.addEventListener("input", () => this.updatePreview())
    }
    if (this.startDateInput) {
      this.startDateInput.addEventListener("change", () => this.updatePreview())
    }
  }

  updatePreview() {
    const actualPage = parseInt(this.currentPageInput?.value) || this.firstPageValue
    const startDate = this.startDateInput?.value ? new Date(this.startDateInput.value + "T00:00:00") : new Date()
    const targetDate = new Date(this.targetDateValue + "T00:00:00")

    // Calculate pages remaining from actual page number
    const pagesRemaining = Math.max(this.lastPageValue - actualPage, 0)
    const days = this.countReadingDays(startDate, targetDate)
    const pagesPerDay = days > 0 ? Math.ceil(pagesRemaining / days) : 0

    if (this.hasPagesRemainingTarget) {
      this.pagesRemainingTarget.textContent = pagesRemaining
    }
    if (this.hasDaysRemainingTarget) {
      this.daysRemainingTarget.textContent = days
    }
    if (this.hasPagesPerDayTarget) {
      this.pagesPerDayTarget.textContent = pagesPerDay
    }
    if (this.hasMinutesPerDayTarget) {
      // Rough estimate: assume 250 words/page and 200 WPM
      const wordsRemaining = pagesRemaining * 250
      const minutesRemaining = wordsRemaining / 200
      const minutesPerDay = days > 0 ? Math.ceil(minutesRemaining / days) : 0
      this.minutesPerDayTarget.textContent = minutesPerDay
    }
  }

  countReadingDays(startDate, endDate) {
    if (startDate > endDate) return 0

    let count = 0
    const current = new Date(startDate)
    while (current <= endDate) {
      const dayOfWeek = current.getDay()
      const isWeekend = dayOfWeek === 0 || dayOfWeek === 6
      if (this.includeWeekendsValue || !isWeekend) {
        count++
      }
      current.setDate(current.getDate() + 1)
    }
    return count
  }
}
