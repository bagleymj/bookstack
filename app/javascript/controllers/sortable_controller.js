import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="sortable"
export default class extends Controller {
  static values = {
    url: String
  }

  static targets = ["item", "track"]

  connect() {
    this.draggedItem = null
    this.placeholder = null
    this.setupDraggables()
  }

  setupDraggables() {
    this.itemTargets.forEach(item => {
      item.setAttribute("draggable", "true")
      item.addEventListener("dragstart", this.handleDragStart.bind(this))
      item.addEventListener("dragend", this.handleDragEnd.bind(this))
      item.addEventListener("dragover", this.handleDragOver.bind(this))
      item.addEventListener("drop", this.handleDrop.bind(this))
      item.addEventListener("dragenter", this.handleDragEnter.bind(this))
      item.addEventListener("dragleave", this.handleDragLeave.bind(this))
    })

    // Allow dropping on track containers for moving between tracks
    this.trackTargets.forEach(track => {
      track.addEventListener("dragover", this.handleTrackDragOver.bind(this))
      track.addEventListener("drop", this.handleTrackDrop.bind(this))
      track.addEventListener("dragenter", this.handleTrackDragEnter.bind(this))
      track.addEventListener("dragleave", this.handleTrackDragLeave.bind(this))
    })
  }

  handleDragStart(event) {
    this.draggedItem = event.target.closest("[data-sortable-target='item']")
    this.draggedItem.classList.add("opacity-50", "scale-95")

    // Create a custom drag image
    const rect = this.draggedItem.getBoundingClientRect()
    event.dataTransfer.effectAllowed = "move"
    event.dataTransfer.setData("text/plain", this.draggedItem.dataset.id)

    // Create placeholder
    this.placeholder = document.createElement("div")
    this.placeholder.className = "h-16 border-2 border-dashed border-indigo-400 rounded-lg bg-indigo-50 transition-all"
  }

  handleDragEnd(event) {
    if (this.draggedItem) {
      this.draggedItem.classList.remove("opacity-50", "scale-95")
      this.draggedItem = null
    }

    if (this.placeholder && this.placeholder.parentNode) {
      this.placeholder.parentNode.removeChild(this.placeholder)
    }
    this.placeholder = null

    // Remove any lingering drag styles
    this.itemTargets.forEach(item => {
      item.classList.remove("border-indigo-400", "border-t-2")
    })
    this.trackTargets.forEach(track => {
      track.classList.remove("bg-indigo-50")
    })
  }

  handleDragOver(event) {
    event.preventDefault()
    event.dataTransfer.dropEffect = "move"
  }

  handleDragEnter(event) {
    event.preventDefault()
    const item = event.target.closest("[data-sortable-target='item']")
    if (item && item !== this.draggedItem) {
      item.classList.add("border-indigo-400", "border-t-2")
    }
  }

  handleDragLeave(event) {
    const item = event.target.closest("[data-sortable-target='item']")
    if (item) {
      item.classList.remove("border-indigo-400", "border-t-2")
    }
  }

  handleDrop(event) {
    event.preventDefault()
    const dropTarget = event.target.closest("[data-sortable-target='item']")

    if (dropTarget && dropTarget !== this.draggedItem) {
      const track = dropTarget.closest("[data-sortable-target='track']")
      const items = track.querySelector("[data-items]")

      // Insert before the drop target
      items.insertBefore(this.draggedItem, dropTarget)

      // Update positions
      this.savePositions()
    }

    this.handleDragEnd(event)
  }

  handleTrackDragOver(event) {
    event.preventDefault()
    event.dataTransfer.dropEffect = "move"
  }

  handleTrackDragEnter(event) {
    event.preventDefault()
    const track = event.target.closest("[data-sortable-target='track']")
    if (track) {
      track.classList.add("bg-indigo-50")
    }
  }

  handleTrackDragLeave(event) {
    const track = event.target.closest("[data-sortable-target='track']")
    if (track && !track.contains(event.relatedTarget)) {
      track.classList.remove("bg-indigo-50")
    }
  }

  handleTrackDrop(event) {
    event.preventDefault()
    const track = event.target.closest("[data-sortable-target='track']")

    if (track && this.draggedItem) {
      const items = track.querySelector("[data-items]")

      // Append to the end of the track if dropped on track container (not on an item)
      if (!event.target.closest("[data-sortable-target='item']")) {
        items.appendChild(this.draggedItem)
        this.savePositions()
      }
    }

    this.handleDragEnd(event)
  }

  async savePositions() {
    const positions = []

    this.trackTargets.forEach(track => {
      const trackNumber = parseInt(track.dataset.track)
      const items = track.querySelectorAll("[data-sortable-target='item']")

      items.forEach((item, index) => {
        positions.push({
          id: parseInt(item.dataset.id),
          position: index + 1,
          track: trackNumber
        })
      })
    })

    try {
      const response = await fetch(this.urlValue, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content,
          "Accept": "application/json"
        },
        credentials: "same-origin",
        body: JSON.stringify({ positions })
      })

      if (!response.ok) {
        throw new Error("Failed to save positions")
      }

      // Show brief success indicator
      this.showToast("Order updated", "success")
    } catch (error) {
      console.error("Error saving positions:", error)
      this.showToast("Failed to save order", "error")
      // Optionally reload to restore original order
      // window.location.reload()
    }
  }

  showToast(message, type) {
    const toast = document.createElement("div")
    toast.className = `fixed bottom-4 right-4 px-4 py-2 rounded-lg text-white text-sm transition-opacity duration-300 ${
      type === "success" ? "bg-green-600" : "bg-red-600"
    }`
    toast.textContent = message
    document.body.appendChild(toast)

    setTimeout(() => {
      toast.style.opacity = "0"
      setTimeout(() => toast.remove(), 300)
    }, 2000)
  }
}
