import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["track", "rangeHighlight", "minHandle", "maxHandle", "minInput", "maxInput", "recommendedIndicator"]
  static values = {
    min: { type: Number, default: 1 },
    max: { type: Number, default: 0 },
    currentMin: { type: Number, default: 1 },
    currentMax: { type: Number, default: 0 },
    recommendedMin: { type: Number, default: 0 },
    recommendedMax: { type: Number, default: 0 }
  }

  connect() {
    this.dragging = null // "min" or "max"
    this.boundMouseMove = this.handleMouseMove.bind(this)
    this.boundMouseUp = this.handleMouseUp.bind(this)
    this.boundTouchMove = this.handleTouchMove.bind(this)
    this.boundTouchEnd = this.handleMouseUp.bind(this)

    this.render()
  }

  disconnect() {
    document.removeEventListener("mousemove", this.boundMouseMove)
    document.removeEventListener("mouseup", this.boundMouseUp)
    document.removeEventListener("touchmove", this.boundTouchMove)
    document.removeEventListener("touchend", this.boundTouchEnd)
  }

  // Value change callbacks
  maxValueChanged() { this.render() }
  currentMinValueChanged() { this.render() }
  currentMaxValueChanged() { this.render() }
  recommendedMinValueChanged() { this.render() }
  recommendedMaxValueChanged() { this.render() }

  // --- Drag handling ---

  startDragMin(event) {
    event.preventDefault()
    this.dragging = "min"
    document.addEventListener("mousemove", this.boundMouseMove)
    document.addEventListener("mouseup", this.boundMouseUp)
    document.addEventListener("touchmove", this.boundTouchMove, { passive: false })
    document.addEventListener("touchend", this.boundTouchEnd)
  }

  startDragMax(event) {
    event.preventDefault()
    this.dragging = "max"
    document.addEventListener("mousemove", this.boundMouseMove)
    document.addEventListener("mouseup", this.boundMouseUp)
    document.addEventListener("touchmove", this.boundTouchMove, { passive: false })
    document.addEventListener("touchend", this.boundTouchEnd)
  }

  handleMouseMove(event) {
    if (!this.dragging) return
    this.updateFromPosition(event.clientX)
  }

  handleTouchMove(event) {
    if (!this.dragging) return
    event.preventDefault()
    this.updateFromPosition(event.touches[0].clientX)
  }

  handleMouseUp() {
    this.dragging = null
    document.removeEventListener("mousemove", this.boundMouseMove)
    document.removeEventListener("mouseup", this.boundMouseUp)
    document.removeEventListener("touchmove", this.boundTouchMove)
    document.removeEventListener("touchend", this.boundTouchEnd)
  }

  updateFromPosition(clientX) {
    if (!this.hasTrackTarget) return
    const rect = this.trackTarget.getBoundingClientRect()
    const ratio = Math.max(0, Math.min(1, (clientX - rect.left) / rect.width))
    const value = Math.round(this.minValue + ratio * (this.maxValue - this.minValue))

    if (this.dragging === "min") {
      const clamped = Math.min(value, this.currentMaxValue - 1)
      this.currentMinValue = Math.max(this.minValue, clamped)
      this.syncToInput("min")
    } else if (this.dragging === "max") {
      const clamped = Math.max(value, this.currentMinValue + 1)
      this.currentMaxValue = Math.min(this.maxValue, clamped)
      this.syncToInput("max")
    }
  }

  // --- Input handling ---

  inputMin() {
    const val = parseInt(this.minInputTarget.value, 10)
    if (!isNaN(val) && val >= 1 && val < this.currentMaxValue) {
      if (val < this.minValue) this.minValue = val
      this.currentMinValue = val
      this.syncToInput("min")
    }
  }

  inputMax() {
    const val = parseInt(this.maxInputTarget.value, 10)
    if (!isNaN(val) && val > this.currentMinValue) {
      // Expand slider range if user typed a value beyond the original max
      if (val > this.maxValue) this.maxValue = val
      this.currentMaxValue = val
      this.syncToInput("max")
    }
  }

  // --- Sync and render ---

  syncToInput(which) {
    const formFirstPage = document.getElementById("book_first_page")
    const formLastPage = document.getElementById("book_last_page")

    if (which === "min" || which === "both") {
      if (this.hasMinInputTarget) this.minInputTarget.value = this.currentMinValue
      if (formFirstPage) {
        formFirstPage.value = this.currentMinValue
        formFirstPage.dispatchEvent(new Event("change", { bubbles: true }))
      }
    }

    if (which === "max" || which === "both") {
      if (this.hasMaxInputTarget) this.maxInputTarget.value = this.currentMaxValue
      if (formLastPage) {
        formLastPage.value = this.currentMaxValue
        formLastPage.dispatchEvent(new Event("change", { bubbles: true }))
      }
    }
  }

  render() {
    if (this.maxValue <= 0) {
      // No page count set yet — hide slider
      if (this.hasTrackTarget) this.trackTarget.classList.add("opacity-30", "pointer-events-none")
      return
    }

    if (this.hasTrackTarget) this.trackTarget.classList.remove("opacity-30", "pointer-events-none")

    const range = this.maxValue - this.minValue
    if (range <= 0) return

    const minPercent = ((this.currentMinValue - this.minValue) / range) * 100
    const maxPercent = ((this.currentMaxValue - this.minValue) / range) * 100

    // Position handles
    if (this.hasMinHandleTarget) this.minHandleTarget.style.left = `${minPercent}%`
    if (this.hasMaxHandleTarget) this.maxHandleTarget.style.left = `${maxPercent}%`

    // Highlight active range
    if (this.hasRangeHighlightTarget) {
      this.rangeHighlightTarget.style.left = `${minPercent}%`
      this.rangeHighlightTarget.style.width = `${maxPercent - minPercent}%`
    }

    // Recommended range indicator
    if (this.hasRecommendedIndicatorTarget) {
      if (this.recommendedMinValue > 0 && this.recommendedMaxValue > 0) {
        const recMinPercent = ((this.recommendedMinValue - this.minValue) / range) * 100
        const recMaxPercent = ((this.recommendedMaxValue - this.minValue) / range) * 100
        this.recommendedIndicatorTarget.style.left = `${recMinPercent}%`
        this.recommendedIndicatorTarget.style.width = `${recMaxPercent - recMinPercent}%`
        this.recommendedIndicatorTarget.classList.remove("hidden")
      } else {
        this.recommendedIndicatorTarget.classList.add("hidden")
      }
    }

    // Update inputs
    if (this.hasMinInputTarget) this.minInputTarget.value = this.currentMinValue
    if (this.hasMaxInputTarget) this.maxInputTarget.value = this.currentMaxValue
  }
}
