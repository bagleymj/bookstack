import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "display", "statusText",
    "toggleButton", "toggleIcon", "toggleText",
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

  toggle() {
    if (this.running) {
      this.stop()
    } else {
      this.start()
    }
  }

  start() {
    this.running = true
    this.startTime = Date.now()
    this.elapsedSeconds = 0

    this.saveToStorage()
    this.startInterval()
    this.updateUI()
  }

  stop() {
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

    // Update toggle button appearance
    if (this.hasToggleButtonTarget) {
      if (this.running) {
        // Switch to red stop button
        this.toggleButtonTarget.classList.remove("bg-green-600", "hover:bg-green-500", "focus-visible:outline-green-600")
        this.toggleButtonTarget.classList.add("bg-red-600", "hover:bg-red-500", "focus-visible:outline-red-600")
      } else {
        // Switch to green start button
        this.toggleButtonTarget.classList.remove("bg-red-600", "hover:bg-red-500", "focus-visible:outline-red-600")
        this.toggleButtonTarget.classList.add("bg-green-600", "hover:bg-green-500", "focus-visible:outline-green-600")
      }
    }

    // Update toggle button text
    if (this.hasToggleTextTarget) {
      this.toggleTextTarget.textContent = this.running ? "Stop" : "Start"
    }

    // Update toggle button icon
    if (this.hasToggleIconTarget) {
      if (this.running) {
        // Stop icon (square inside circle)
        this.toggleIconTarget.innerHTML = `
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 12a9 9 0 11-18 0 9 9 0 0118 0z"/>
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 10a1 1 0 011-1h4a1 1 0 011 1v4a1 1 0 01-1 1h-4a1 1 0 01-1-1v-4z"/>
        `
      } else {
        // Play icon (triangle inside circle)
        this.toggleIconTarget.innerHTML = `
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M14.752 11.168l-3.197-2.132A1 1 0 0010 9.87v4.263a1 1 0 001.555.832l3.197-2.132a1 1 0 000-1.664z"/>
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 12a9 9 0 11-18 0 9 9 0 0118 0z"/>
        `
      }
    }
  }

  showCompletionForm() {
    // Hide timer controls and show completion form
    if (this.hasToggleButtonTarget) this.toggleButtonTarget.classList.add("hidden")
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
