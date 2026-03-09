import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["content", "icon"]
  static values = { open: { type: Boolean, default: false } }

  toggle() {
    this.openValue = !this.openValue
    this.update()
  }

  update() {
    if (this.openValue) {
      this.contentTarget.classList.remove("hidden")
      this.iconTarget.classList.add("rotate-90")
    } else {
      this.contentTarget.classList.add("hidden")
      this.iconTarget.classList.remove("rotate-90")
    }
  }
}
