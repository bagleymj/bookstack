import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["filterBtn", "row", "checkbox", "selectedCount", "field"]

  connect() {
    this.syncFields()
    this.updateCount()
  }

  filterAll() {
    this.rowTargets.forEach(row => row.classList.remove("hidden"))
    this.highlightButton("all")
    this.updateCount()
  }

  filterShelf(event) {
    const shelf = event.currentTarget.dataset.shelf
    this.rowTargets.forEach(row => {
      row.classList.toggle("hidden", row.dataset.shelf !== shelf)
    })
    this.highlightButton(shelf)
    this.updateCount()
  }

  selectVisible() {
    this.rowTargets.forEach(row => {
      if (!row.classList.contains("hidden")) {
        const cb = row.querySelector("[data-import-filter-target='checkbox']")
        if (cb && !cb.disabled) cb.checked = true
      }
    })
    this.syncFields()
    this.updateCount()
  }

  deselectAll() {
    this.checkboxTargets.forEach(cb => {
      if (!cb.disabled) cb.checked = false
    })
    this.syncFields()
    this.updateCount()
  }

  updateCount() {
    this.syncFields()
    const checked = this.checkboxTargets.filter(cb => cb.checked && !cb.disabled).length
    if (this.hasSelectedCountTarget) {
      this.selectedCountTarget.textContent = `${checked} selected`
    }
  }

  // Enable/disable hidden fields based on checkbox state so only
  // checked rows submit their data
  syncFields() {
    this.rowTargets.forEach(row => {
      const cb = row.querySelector("[data-import-filter-target='checkbox']")
      const checked = cb?.checked && !cb?.disabled
      row.querySelectorAll("[data-import-filter-target='field']").forEach(field => {
        field.disabled = !checked
      })
    })
  }

  highlightButton(activeShelf) {
    this.filterBtnTargets.forEach(btn => {
      const isActive = btn.dataset.shelf === activeShelf
      btn.classList.toggle("bg-indigo-100", isActive)
      btn.classList.toggle("text-indigo-700", isActive)
      btn.classList.toggle("bg-gray-100", !isActive)
      btn.classList.toggle("text-gray-700", !isActive)
    })
  }
}
