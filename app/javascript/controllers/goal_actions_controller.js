import { Controller } from "@hotwired/stimulus"

// Handles postpone and unlock actions on reading goal cards
export default class extends Controller {
  async postpone(event) {
    event.preventDefault()
    const goalId = event.currentTarget.dataset.goalId

    if (!confirm("Postpone this book? It will return to the queue and skip the next scheduling week.")) {
      return
    }

    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content

    try {
      const response = await fetch(`/api/v1/reading_goals/${goalId}/postpone`, {
        method: "POST",
        headers: {
          "X-CSRF-Token": csrfToken,
          "Accept": "application/json"
        },
        credentials: "same-origin"
      })

      if (response.ok) {
        window.location.reload()
      } else {
        const data = await response.json()
        this.showToast(data.errors?.[0] || "Failed to postpone", "error")
      }
    } catch (error) {
      this.showToast("Network error", "error")
    }
  }

  async unlock(event) {
    event.preventDefault()
    const goalId = event.currentTarget.dataset.goalId

    if (!confirm("Unlock this book? It will return to the auto-scheduled queue.")) {
      return
    }

    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content

    try {
      const response = await fetch(`/api/v1/reading_goals/${goalId}/unlock`, {
        method: "POST",
        headers: {
          "X-CSRF-Token": csrfToken,
          "Accept": "application/json"
        },
        credentials: "same-origin"
      })

      if (response.ok) {
        window.location.reload()
      } else {
        const data = await response.json()
        this.showToast(data.errors?.[0] || "Failed to unlock", "error")
      }
    } catch (error) {
      this.showToast("Network error", "error")
    }
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
