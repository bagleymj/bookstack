import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "display", "statusText",
    "startButton", "finishButton",
    "progressInfo", "completionForm", "cancelLink",
    "durationField", "endPageField", "finalTime"
  ]

  static values = {
    bookId: String
  }

  connect() {
    this.running = false
    this.startTime = null
    this.elapsedSeconds = 0
    this.interval = null

    // Check for saved session
    this.loadFromStorage()
  }

  disconnect() {
    this.stopInterval()
  }

  start() {
    this.running = true
    this.startTime = Date.now()
    this.elapsedSeconds = 0

    this.saveToStorage()
    this.startInterval()
    this.updateUI()
  }

  finish() {
    if (!this.running) return

    // Calculate final elapsed time
    this.elapsedSeconds += Math.floor((Date.now() - this.startTime) / 1000)

    this.running = false
    this.stopInterval()
    this.clearStorage()

    // Update form fields
    if (this.hasDurationFieldTarget) {
      this.durationFieldTarget.value = this.elapsedSeconds
    }
    if (this.hasFinalTimeTarget) {
      this.finalTimeTarget.textContent = this.formatTime(this.elapsedSeconds)
    }

    this.showCompletionForm()
  }

  discard() {
    this.clearStorage()
  }

  // Private methods

  startInterval() {
    this.interval = setInterval(() => this.updateDisplay(), 1000)
  }

  stopInterval() {
    if (this.interval) {
      clearInterval(this.interval)
      this.interval = null
    }
  }

  updateDisplay() {
    let totalSeconds = this.elapsedSeconds
    if (this.running) {
      totalSeconds += Math.floor((Date.now() - this.startTime) / 1000)
    }

    if (this.hasDisplayTarget) {
      this.displayTarget.textContent = this.formatTime(totalSeconds)
    }
  }

  formatTime(totalSeconds) {
    const hours = Math.floor(totalSeconds / 3600)
    const minutes = Math.floor((totalSeconds % 3600) / 60)
    const seconds = totalSeconds % 60

    const pad = (n) => n.toString().padStart(2, '0')

    if (hours > 0) {
      return `${pad(hours)}:${pad(minutes)}:${pad(seconds)}`
    }
    return `${pad(minutes)}:${pad(seconds)}`
  }

  updateUI() {
    // Update status text
    if (this.hasStatusTextTarget) {
      if (!this.running) {
        this.statusTextTarget.textContent = "Press Start to begin reading"
      } else {
        this.statusTextTarget.textContent = "Timer running..."
      }
    }

    // Update button visibility
    if (this.hasStartButtonTarget) {
      this.startButtonTarget.classList.toggle("hidden", this.running)
    }
    if (this.hasFinishButtonTarget) {
      this.finishButtonTarget.classList.toggle("hidden", !this.running)
    }
  }

  showCompletionForm() {
    // Hide timer controls and show completion form
    if (this.hasStartButtonTarget) this.startButtonTarget.classList.add("hidden")
    if (this.hasFinishButtonTarget) this.finishButtonTarget.classList.add("hidden")
    if (this.hasProgressInfoTarget) this.progressInfoTarget.classList.add("hidden")
    if (this.hasCancelLinkTarget) this.cancelLinkTarget.classList.add("hidden")

    if (this.hasCompletionFormTarget) {
      this.completionFormTarget.classList.remove("hidden")
    }

    if (this.hasStatusTextTarget) {
      this.statusTextTarget.textContent = "Session complete!"
    }

    // Focus the end page field
    if (this.hasEndPageFieldTarget) {
      this.endPageFieldTarget.focus()
      this.endPageFieldTarget.select()
    }
  }

  saveToStorage() {
    const data = {
      bookId: this.bookIdValue,
      startTime: this.startTime,
      elapsedSeconds: this.elapsedSeconds,
      running: this.running
    }
    localStorage.setItem('bookstack_timer', JSON.stringify(data))
  }

  loadFromStorage() {
    const data = localStorage.getItem('bookstack_timer')
    if (!data) return

    const stored = JSON.parse(data)

    // Only restore if it's for the same book
    if (stored.bookId !== this.bookIdValue) return

    this.elapsedSeconds = stored.elapsedSeconds || 0
    this.running = stored.running || false

    if (this.running) {
      // Was running - calculate elapsed and resume
      this.startTime = stored.startTime
      const additionalSeconds = Math.floor((Date.now() - this.startTime) / 1000)
      this.elapsedSeconds += additionalSeconds
      this.startTime = Date.now()
      this.startInterval()
      this.updateUI()
    }
  }

  clearStorage() {
    localStorage.removeItem('bookstack_timer')
  }
}
