import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { startedAt: String }
  static targets = ["timer", "completionForm", "endPageField", "stopButton", "pauseButton", "pauseIcon", "pauseText", "pauseBadge"]

  connect() {
    this.startTime = new Date(this.startedAtValue)
    this.paused = false
    this.pausedDuration = 0 // total ms spent paused
    this.pauseStartTime = null
    this.updateTimer()
    this.interval = setInterval(() => this.updateTimer(), 1000)
  }

  disconnect() {
    if (this.interval) clearInterval(this.interval)
  }

  updateTimer() {
    if (this.paused) return

    const now = Date.now()
    const totalElapsed = now - this.startTime.getTime()
    this.frozenElapsed = Math.floor((totalElapsed - this.pausedDuration) / 1000)
    this.timerTargets.forEach(el => el.textContent = this.formatTime(this.frozenElapsed))
  }

  togglePause() {
    if (this.paused) {
      this.resume()
    } else {
      this.pause()
    }
  }

  pause() {
    this.paused = true
    this.pauseStartTime = Date.now()
    if (this.interval) clearInterval(this.interval)
    this.interval = null

    // Update UI
    this.timerTargets.forEach(el => el.classList.add("opacity-50"))
    if (this.hasPauseIconTarget) {
      // Switch to play icon
      this.pauseIconTarget.innerHTML = `
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M14.752 11.168l-3.197-2.132A1 1 0 0010 9.87v4.263a1 1 0 001.555.832l3.197-2.132a1 1 0 000-1.664z"/>
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 12a9 9 0 11-18 0 9 9 0 0118 0z"/>
      `
    }
    if (this.hasPauseTextTarget) this.pauseTextTarget.textContent = "Resume"
    if (this.hasPauseBadgeTarget) this.pauseBadgeTarget.classList.remove("hidden")
  }

  resume() {
    if (this.pauseStartTime) {
      this.pausedDuration += Date.now() - this.pauseStartTime
      this.pauseStartTime = null
    }
    this.paused = false

    // Restart timer
    this.interval = setInterval(() => this.updateTimer(), 1000)
    this.updateTimer()

    // Update UI
    this.timerTargets.forEach(el => el.classList.remove("opacity-50"))
    if (this.hasPauseIconTarget) {
      // Switch to pause icon
      this.pauseIconTarget.innerHTML = `
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 9v6m4-6v6m7-3a9 9 0 11-18 0 9 9 0 0118 0z"/>
      `
    }
    if (this.hasPauseTextTarget) this.pauseTextTarget.textContent = "Pause"
    if (this.hasPauseBadgeTarget) this.pauseBadgeTarget.classList.add("hidden")
  }

  stop() {
    // If paused, account for final pause duration
    if (this.paused && this.pauseStartTime) {
      this.pausedDuration += Date.now() - this.pauseStartTime
      this.pauseStartTime = null
    }

    if (this.interval) clearInterval(this.interval)
    this.interval = null

    // Calculate final elapsed (excluding paused time)
    const totalElapsed = Date.now() - this.startTime.getTime()
    this.frozenElapsed = Math.floor((totalElapsed - this.pausedDuration) / 1000)
    this.timerTargets.forEach(el => {
      el.textContent = this.formatTime(this.frozenElapsed)
      el.classList.remove("opacity-50")
    })

    this.completionFormTarget.classList.remove("hidden")
    this.stopButtonTarget.classList.add("hidden")
    if (this.hasPauseButtonTarget) this.pauseButtonTarget.classList.add("hidden")
    this.endPageFieldTarget.focus()
  }

  cancelStop() {
    this.completionFormTarget.classList.add("hidden")
    this.stopButtonTarget.classList.remove("hidden")
    if (this.hasPauseButtonTarget) this.pauseButtonTarget.classList.remove("hidden")
    if (!this.interval && !this.paused) {
      // Recalculate startTime to account for frozen period
      const now = Date.now()
      this.startTime = new Date(now - (this.frozenElapsed * 1000 + this.pausedDuration))
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
