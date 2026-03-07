import { Controller } from "@hotwired/stimulus"

// Handles drag-and-drop of book cards onto the pipeline to create reading goals
export default class extends Controller {
  static targets = ["bookCard", "dropZone", "modal", "modalTitle", "bookIdField",
                     "startedOn", "targetDate", "includeWeekends", "modalErrors"]
  static values = {
    createUrl: String
  }

  connect() {
    this.draggedBookId = null
    this.draggedBookTitle = null
  }

  // --- Drag events on book cards ---

  dragStart(event) {
    const card = event.currentTarget
    this.draggedBookId = card.dataset.bookId
    this.draggedBookTitle = card.dataset.bookTitle

    event.dataTransfer.effectAllowed = "copy"
    event.dataTransfer.setData("text/plain", this.draggedBookId)

    card.classList.add("opacity-50", "scale-95")

    // Show the drop zone highlight after a brief delay so it doesn't flash
    // if the user is just clicking
    requestAnimationFrame(() => {
      this.dropZoneTarget.classList.add(
        "ring-2", "ring-indigo-400", "ring-dashed", "bg-indigo-50/50"
      )
    })
  }

  dragEnd(event) {
    event.currentTarget.classList.remove("opacity-50", "scale-95")
    this.clearDropZoneHighlight()
    this.draggedBookId = null
    this.draggedBookTitle = null
  }

  // --- Drop zone events ---

  dragOver(event) {
    event.preventDefault()
    event.dataTransfer.dropEffect = "copy"
  }

  dragEnter(event) {
    event.preventDefault()
    this.dropZoneTarget.classList.add(
      "ring-2", "ring-indigo-500", "bg-indigo-50"
    )
    this.dropZoneTarget.classList.remove("ring-dashed", "ring-indigo-400", "bg-indigo-50/50")
  }

  dragLeave(event) {
    // Only react when actually leaving the drop zone (not entering a child)
    if (!this.dropZoneTarget.contains(event.relatedTarget)) {
      this.dropZoneTarget.classList.remove("ring-2", "ring-indigo-500", "bg-indigo-50")
      this.dropZoneTarget.classList.add(
        "ring-2", "ring-indigo-400", "ring-dashed", "bg-indigo-50/50"
      )
    }
  }

  drop(event) {
    event.preventDefault()
    this.clearDropZoneHighlight()

    const bookId = event.dataTransfer.getData("text/plain")
    if (!bookId) return

    this.openModal(bookId, this.draggedBookTitle)
  }

  // --- Modal ---

  openModal(bookId, bookTitle) {
    this.bookIdFieldTarget.value = bookId
    this.modalTitleTarget.textContent = bookTitle || "Selected Book"
    this.startedOnTarget.value = this.todayString()
    this.targetDateTarget.value = ""
    this.targetDateTarget.min = this.tomorrowString()
    this.includeWeekendsTarget.checked = false
    this.clearErrors()

    this.modalTarget.classList.remove("hidden")
    this.targetDateTarget.focus()
  }

  closeModal() {
    this.modalTarget.classList.add("hidden")
    this.clearErrors()
  }

  // Close on backdrop click
  backdropClick(event) {
    if (event.target === this.modalTarget) {
      this.closeModal()
    }
  }

  // Close on Escape
  modalKeydown(event) {
    if (event.key === "Escape") {
      this.closeModal()
    }
  }

  async submitGoal(event) {
    event.preventDefault()
    this.clearErrors()

    const bookId = this.bookIdFieldTarget.value
    const startedOn = this.startedOnTarget.value
    const targetDate = this.targetDateTarget.value
    const includeWeekends = this.includeWeekendsTarget.checked

    if (!targetDate) {
      this.showErrors(["Target completion date is required"])
      return
    }

    try {
      const response = await fetch(this.createUrlValue, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content,
          "Accept": "application/json"
        },
        credentials: "same-origin",
        body: JSON.stringify({
          reading_goal: {
            book_id: bookId,
            started_on: startedOn,
            target_completion_date: targetDate,
            include_weekends: includeWeekends
          }
        })
      })

      if (response.ok) {
        this.closeModal()
        this.showToast("Reading goal created!", "success")
        // Reload to show the new goal in the pipeline
        setTimeout(() => window.location.reload(), 500)
      } else {
        const data = await response.json()
        this.showErrors(data.errors || ["Failed to create reading goal"])
      }
    } catch (error) {
      console.error("Error creating goal:", error)
      this.showErrors(["Something went wrong. Please try again."])
    }
  }

  // --- Helpers ---

  clearDropZoneHighlight() {
    this.dropZoneTarget.classList.remove(
      "ring-2", "ring-indigo-400", "ring-indigo-500",
      "ring-dashed", "bg-indigo-50", "bg-indigo-50/50"
    )
  }

  showErrors(messages) {
    this.modalErrorsTarget.innerHTML = messages
      .map(m => `<li>${this.escapeHtml(m)}</li>`)
      .join("")
    this.modalErrorsTarget.parentElement.classList.remove("hidden")
  }

  clearErrors() {
    this.modalErrorsTarget.innerHTML = ""
    this.modalErrorsTarget.parentElement.classList.add("hidden")
  }

  showToast(message, type) {
    const toast = document.createElement("div")
    toast.className = `fixed bottom-4 right-4 px-4 py-2 rounded-lg text-white text-sm z-50 transition-opacity duration-300 ${
      type === "success" ? "bg-green-600" : "bg-red-600"
    }`
    toast.textContent = message
    document.body.appendChild(toast)

    setTimeout(() => {
      toast.style.opacity = "0"
      setTimeout(() => toast.remove(), 300)
    }, 2000)
  }

  todayString() {
    return new Date().toISOString().split("T")[0]
  }

  tomorrowString() {
    const d = new Date()
    d.setDate(d.getDate() + 1)
    return d.toISOString().split("T")[0]
  }

  escapeHtml(str) {
    const div = document.createElement("div")
    div.textContent = str
    return div.innerHTML
  }
}
