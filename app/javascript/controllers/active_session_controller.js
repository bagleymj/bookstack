import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { startedAt: String }
  static targets = ["timer", "completionForm", "endPageField", "stopButton"]

  connect() {
    this.startTime = new Date(this.startedAtValue)
    this.updateTimer()
    this.interval = setInterval(() => this.updateTimer(), 1000)
  }

  disconnect() {
    if (this.interval) clearInterval(this.interval)
  }

  updateTimer() {
    this.frozenElapsed = Math.floor((Date.now() - this.startTime.getTime()) / 1000)
    this.timerTargets.forEach(el => el.textContent = this.formatTime(this.frozenElapsed))
  }

  stop() {
    if (this.interval) clearInterval(this.interval)
    this.interval = null
    this.completionFormTarget.classList.remove("hidden")
    this.stopButtonTarget.classList.add("hidden")
    this.endPageFieldTarget.focus()
  }

  cancelStop() {
    this.completionFormTarget.classList.add("hidden")
    this.stopButtonTarget.classList.remove("hidden")
    if (!this.interval) {
      this.startTime = new Date(Date.now() - this.frozenElapsed * 1000)
      this.interval = setInterval(() => this.updateTimer(), 1000)
    }
  }

  formatTime(totalSeconds) {
    const hours = Math.floor(totalSeconds / 3600)
    const minutes = Math.floor((totalSeconds % 3600) / 60)
    const seconds = totalSeconds % 60
    const pad = n => String(n).padStart(2, "0")

    if (hours > 0) {
      return `${hours}:${pad(minutes)}:${pad(seconds)}`
    }
    return `${pad(minutes)}:${pad(seconds)}`
  }
}
