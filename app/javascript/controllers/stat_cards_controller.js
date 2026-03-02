import { Controller } from "@hotwired/stimulus"

const STORAGE_KEY = "bookstack_stat_cards"

export default class extends Controller {
  static targets = ["card", "toggle", "panel"]
  static values = { defaults: String }

  connect() {
    this.preferences = this.loadPreferences()
    this.applyVisibility()
    this.syncToggles()

    this.boundKeydown = this.handleKeydown.bind(this)
    document.addEventListener("keydown", this.boundKeydown)
  }

  disconnect() {
    document.removeEventListener("keydown", this.boundKeydown)
  }

  togglePanel() {
    this.panelTarget.classList.toggle("hidden")
  }

  toggleStat(event) {
    const key = event.target.dataset.statKey
    this.preferences[key] = event.target.checked
    this.savePreferences()
    this.applyVisibility()
  }

  resetDefaults() {
    localStorage.removeItem(STORAGE_KEY)
    this.preferences = JSON.parse(this.defaultsValue)
    this.savePreferences()
    this.applyVisibility()
    this.syncToggles()
  }

  // Private

  handleKeydown(event) {
    if (event.key === "Escape" && !this.panelTarget.classList.contains("hidden")) {
      this.panelTarget.classList.add("hidden")
    }
  }

  loadPreferences() {
    const defaults = JSON.parse(this.defaultsValue)
    const stored = localStorage.getItem(STORAGE_KEY)
    if (stored) {
      return { ...defaults, ...JSON.parse(stored) }
    }
    return defaults
  }

  savePreferences() {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(this.preferences))
  }

  applyVisibility() {
    this.cardTargets.forEach(card => {
      const key = card.dataset.statKey
      card.classList.toggle("hidden", !this.preferences[key])
    })
  }

  syncToggles() {
    this.toggleTargets.forEach(toggle => {
      const key = toggle.dataset.statKey
      toggle.checked = !!this.preferences[key]
    })
  }
}
