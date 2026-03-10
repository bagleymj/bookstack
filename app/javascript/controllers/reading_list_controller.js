import { Controller } from "@hotwired/stimulus"

// Drag-and-drop reordering for the reading list "Up Next" section
export default class extends Controller {
  static values = { url: String }
  static targets = ["item", "list", "dates"]

  connect() {
    this.draggedItem = null
    this.placeholder = null
    this.setupDraggables()
  }

  setupDraggables() {
    this.itemTargets.forEach(item => {
      item.addEventListener("dragstart", this.handleDragStart.bind(this))
      item.addEventListener("dragend", this.handleDragEnd.bind(this))
      item.addEventListener("dragover", this.handleDragOver.bind(this))
      item.addEventListener("drop", this.handleDrop.bind(this))
      item.addEventListener("dragenter", this.handleDragEnter.bind(this))
      item.addEventListener("dragleave", this.handleDragLeave.bind(this))
    })
  }

  handleDragStart(event) {
    this.draggedItem = event.target.closest("[data-reading-list-target='item']")
    this.draggedItem.classList.add("opacity-50", "scale-95")
    event.dataTransfer.effectAllowed = "move"
    event.dataTransfer.setData("text/plain", this.draggedItem.dataset.goalId)
  }

  handleDragEnd() {
    if (this.draggedItem) {
      this.draggedItem.classList.remove("opacity-50", "scale-95")
      this.draggedItem = null
    }
    this.itemTargets.forEach(item => {
      item.classList.remove("border-indigo-400", "border-t-2")
    })
  }

  handleDragOver(event) {
    event.preventDefault()
    event.dataTransfer.dropEffect = "move"
  }

  handleDragEnter(event) {
    event.preventDefault()
    const item = event.target.closest("[data-reading-list-target='item']")
    if (item && item !== this.draggedItem) {
      item.classList.add("border-indigo-400", "border-t-2")
    }
  }

  handleDragLeave(event) {
    const item = event.target.closest("[data-reading-list-target='item']")
    if (item) {
      item.classList.remove("border-indigo-400", "border-t-2")
    }
  }

  handleDrop(event) {
    event.preventDefault()
    const dropTarget = event.target.closest("[data-reading-list-target='item']")

    if (dropTarget && dropTarget !== this.draggedItem && this.hasListTarget) {
      this.listTarget.insertBefore(this.draggedItem, dropTarget)
      this.savePositions()
    }

    this.handleDragEnd()
  }

  async removeItem(event) {
    const goalId = event.currentTarget.dataset.goalId
    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content

    try {
      const response = await fetch(`/api/v1/reading_list/${goalId}`, {
        method: "DELETE",
        headers: {
          "X-CSRF-Token": csrfToken,
          "Accept": "application/json"
        },
        credentials: "same-origin"
      })

      if (response.ok) {
        // Reload to reflect changes
        window.location.reload()
      }
    } catch (error) {
      console.error("Error removing from list:", error)
    }
  }

  async savePositions() {
    const items = this.itemTargets
    const positions = items.map((item, index) => ({
      id: parseInt(item.dataset.goalId),
      position: index + 1
    }))

    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content

    try {
      const response = await fetch(this.urlValue, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": csrfToken,
          "Accept": "application/json"
        },
        credentials: "same-origin",
        body: JSON.stringify({ positions })
      })

      if (response.ok) {
        const data = await response.json()
        this.updateDates(data.goals)
        this.showToast("Order updated", "success")
        document.dispatchEvent(new CustomEvent("pipeline:refresh"))
      } else {
        this.showToast("Failed to save order", "error")
      }
    } catch (error) {
      console.error("Error saving positions:", error)
      this.showToast("Failed to save order", "error")
    }
  }

  updateDates(goals) {
    this.datesTargets.forEach(el => {
      const goalId = parseInt(el.dataset.goalId)
      const goal = goals.find(g => g.id === goalId)
      if (goal && goal.start_date && goal.end_date) {
        const start = new Date(goal.start_date + "T00:00:00")
        const end = new Date(goal.end_date + "T00:00:00")
        const fmt = (d) => d.toLocaleDateString("en-US", { month: "short", day: "numeric" })
        el.textContent = `${fmt(start)} - ${fmt(end)}`
        el.classList.remove("text-amber-600")
        el.classList.add("text-indigo-600")
      }
    })
  }

  showToast(message, type) {
    const toast = document.createElement("div")
    toast.className = `fixed bottom-20 right-4 md:bottom-4 px-4 py-2 rounded-lg text-white text-sm transition-opacity duration-300 z-50 ${
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
