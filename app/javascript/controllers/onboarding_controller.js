import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "step", "indicator", "backButton", "nextButton", "submitButton",
    "speedCustom",
    "goalValuePanel", "goalValueLabel", "goalPresets", "goalCustom", "goalCustomInput", "goalUnit",
    "derivedInfo", "derivedMinutes"
  ]

  static goalConfigs = {
    books_per_year: {
      label: "How many books per year?",
      unit: "books per year",
      daysInPeriod: 365,
      presets: [
        { value: 12, label: "12", sub: "1/month" },
        { value: 24, label: "24", sub: "2/month" },
        { value: 52, label: "52", sub: "1/week" }
      ]
    },
    books_per_month: {
      label: "How many books per month?",
      unit: "books per month",
      daysInPeriod: 30.44,
      presets: [
        { value: 1, label: "1", sub: "" },
        { value: 2, label: "2", sub: "" },
        { value: 4, label: "4", sub: "1/week" }
      ]
    },
    books_per_week: {
      label: "How many books per week?",
      unit: "books per week",
      daysInPeriod: 7,
      presets: [
        { value: 1, label: "1", sub: "" },
        { value: 2, label: "2", sub: "" },
        { value: 3, label: "3", sub: "" }
      ]
    },
    minutes_per_day: {
      label: "How many minutes per day?",
      unit: "minutes per day",
      daysInPeriod: null,
      presets: [
        { value: 15, label: "15 min", sub: "" },
        { value: 30, label: "30 min", sub: "" },
        { value: 60, label: "1 hour", sub: "" }
      ]
    }
  }

  connect() {
    this.currentStep = 0
    this.totalSteps = this.stepTargets.length
    this.selectedGoalType = null
    this.showStep(0)
  }

  next() {
    if (this.currentStep < this.totalSteps - 1) {
      this.currentStep++
      this.showStep(this.currentStep)
    }
  }

  back() {
    if (this.currentStep > 0) {
      this.currentStep--
      this.showStep(this.currentStep)
    }
  }

  showStep(index) {
    this.stepTargets.forEach((step, i) => {
      step.classList.toggle("hidden", i !== index)
    })

    this.indicatorTargets.forEach((dot, i) => {
      dot.className = i <= index
        ? "w-8 h-1 rounded-full bg-indigo-600"
        : "w-8 h-1 rounded-full bg-gray-200"
    })

    this.backButtonTarget.classList.toggle("invisible", index === 0)
    this.nextButtonTarget.classList.toggle("hidden", index === this.totalSteps - 1)
    this.submitButtonTarget.classList.toggle("hidden", index !== this.totalSteps - 1)
  }

  // -- Speed presets --
  selectSpeed(event) {
    const value = event.currentTarget.dataset.value
    this.element.querySelector('[name="user[default_reading_speed_wpm]"]').value = value
    this._updatePresetButtons(event.currentTarget, "click->onboarding#selectSpeed")
    if (this.hasSpeedCustomTarget) this.speedCustomTarget.classList.add("hidden")
    this._calculateDerivedMinutes()
  }

  selectSpeedCustom() {
    this._deselectPresets("click->onboarding#selectSpeed")
    this._deselectPresets("click->onboarding#selectSpeedCustom")
    if (this.hasSpeedCustomTarget) {
      this.speedCustomTarget.classList.remove("hidden")
      this.speedCustomTarget.querySelector("input")?.focus()
    }
  }

  syncSpeedInput(event) {
    this.element.querySelector('[name="user[default_reading_speed_wpm]"]').value = event.target.value
    this._calculateDerivedMinutes()
  }

  // -- Concurrent books --
  selectConcurrent(event) {
    const value = event.currentTarget.dataset.value
    this.element.querySelector('[name="user[max_concurrent_books]"]').value = value
    this._updatePresetButtons(event.currentTarget, "click->onboarding#selectConcurrent")
  }

  // -- Flexible goal type --
  selectGoalType(event) {
    const type = event.currentTarget.dataset.type
    this.selectedGoalType = type
    const config = this.constructor.goalConfigs[type]

    // Update type hidden field
    this.element.querySelector('[name="user[reading_pace_type]"]').value = type

    // Highlight selected card
    this.element.querySelectorAll("[data-action='click->onboarding#selectGoalType']").forEach(btn => {
      btn.classList.remove("ring-2", "ring-indigo-600", "bg-indigo-50", "selected")
      btn.classList.add("bg-white")
    })
    event.currentTarget.classList.add("ring-2", "ring-indigo-600", "bg-indigo-50", "selected")
    event.currentTarget.classList.remove("bg-white")

    // Show value panel
    this.goalValuePanelTarget.classList.remove("hidden")
    this.goalValueLabelTarget.textContent = config.label
    this.goalUnitTarget.textContent = config.unit

    // Build preset buttons
    this.goalPresetsTarget.innerHTML = ""
    config.presets.forEach(preset => {
      const btn = document.createElement("button")
      btn.type = "button"
      btn.dataset.action = "click->onboarding#selectGoalPreset"
      btn.dataset.value = preset.value
      btn.className = "px-4 py-2.5 rounded-lg border border-gray-200 bg-white text-sm font-medium text-gray-700 hover:border-indigo-300 transition-colors"
      btn.innerHTML = preset.sub
        ? `${preset.label} <span class="text-gray-400 text-xs">${preset.sub}</span>`
        : preset.label
      this.goalPresetsTarget.appendChild(btn)
    })

    // Add custom button
    const customBtn = document.createElement("button")
    customBtn.type = "button"
    customBtn.dataset.action = "click->onboarding#selectGoalCustom"
    customBtn.className = "px-4 py-2.5 rounded-lg border border-gray-200 bg-white text-sm font-medium text-gray-700 hover:border-indigo-300 transition-colors"
    customBtn.textContent = "Custom"
    this.goalPresetsTarget.appendChild(customBtn)

    // Reset value and hide derived info
    this.element.querySelector('[name="user[reading_pace_value]"]').value = ""
    this.goalCustomTarget.classList.add("hidden")
    if (this.hasDerivedInfoTarget) this.derivedInfoTarget.classList.add("hidden")
  }

  selectGoalPreset(event) {
    const value = event.currentTarget.dataset.value
    this.element.querySelector('[name="user[reading_pace_value]"]').value = value

    // Highlight
    this.goalPresetsTarget.querySelectorAll("button").forEach(btn => {
      btn.classList.remove("ring-2", "ring-indigo-600", "bg-indigo-50")
      btn.classList.add("bg-white")
    })
    event.currentTarget.classList.add("ring-2", "ring-indigo-600", "bg-indigo-50")
    event.currentTarget.classList.remove("bg-white")

    this.goalCustomTarget.classList.add("hidden")
    this._calculateDerivedMinutes()
  }

  selectGoalCustom() {
    this.goalPresetsTarget.querySelectorAll("button").forEach(btn => {
      btn.classList.remove("ring-2", "ring-indigo-600", "bg-indigo-50")
      btn.classList.add("bg-white")
    })
    this.goalCustomTarget.classList.remove("hidden")
    this.goalCustomInputTarget.focus()
  }

  syncGoalInput(event) {
    this.element.querySelector('[name="user[reading_pace_value]"]').value = event.target.value
    this._calculateDerivedMinutes()
  }

  clearGoal() {
    this.element.querySelector('[name="user[reading_pace_type]"]').value = ""
    this.element.querySelector('[name="user[reading_pace_value]"]').value = ""
    this.selectedGoalType = null

    // Deselect all cards
    this.element.querySelectorAll("[data-action='click->onboarding#selectGoalType']").forEach(btn => {
      btn.classList.remove("ring-2", "ring-indigo-600", "bg-indigo-50", "selected")
      btn.classList.add("bg-white")
    })

    this.goalValuePanelTarget.classList.add("hidden")
    if (this.hasDerivedInfoTarget) this.derivedInfoTarget.classList.add("hidden")
  }

  // -- Derived minutes calculation --
  _calculateDerivedMinutes() {
    if (!this.selectedGoalType || !this.hasDerivedInfoTarget) return

    const paceValue = parseFloat(this.element.querySelector('[name="user[reading_pace_value]"]').value)
    if (!paceValue || paceValue <= 0) {
      this.derivedInfoTarget.classList.add("hidden")
      return
    }

    const config = this.constructor.goalConfigs[this.selectedGoalType]
    let dailyMinutes

    if (this.selectedGoalType === "minutes_per_day") {
      dailyMinutes = paceValue
    } else {
      const wpp = parseFloat(this.element.querySelector('[name="user[default_words_per_page]"]').value) || 250
      const wpm = parseFloat(this.element.querySelector('[name="user[default_reading_speed_wpm]"]').value) || 200
      const avgPages = 300
      const wordsPerBook = avgPages * wpp
      const minutesPerBook = wordsPerBook / wpm
      const booksPerDay = paceValue / config.daysInPeriod
      dailyMinutes = Math.ceil(minutesPerBook * booksPerDay)
    }

    this.derivedMinutesTarget.textContent = dailyMinutes
    this.derivedInfoTarget.classList.remove("hidden")
  }

  // -- Helpers --
  _updatePresetButtons(selected, action) {
    const container = selected.closest(".flex, .grid")
    if (!container) return
    container.querySelectorAll(`[data-action='${action}']`).forEach(btn => {
      btn.classList.remove("ring-2", "ring-indigo-600", "bg-indigo-50")
      btn.classList.add("bg-white")
    })
    selected.classList.add("ring-2", "ring-indigo-600", "bg-indigo-50")
    selected.classList.remove("bg-white")
  }

  _deselectPresets(action) {
    this.element.querySelectorAll(`[data-action='${action}']`).forEach(btn => {
      btn.classList.remove("ring-2", "ring-indigo-600", "bg-indigo-50")
      btn.classList.add("bg-white")
    })
  }
}
