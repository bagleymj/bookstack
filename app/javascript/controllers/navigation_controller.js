import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["menu", "menuIcon", "closeIcon"]

  toggle() {
    this.menuTarget.classList.toggle("hidden")
    this.menuIconTarget.classList.toggle("hidden")
    this.menuIconTarget.classList.toggle("block")
    this.closeIconTarget.classList.toggle("hidden")
    this.closeIconTarget.classList.toggle("block")
  }
}
