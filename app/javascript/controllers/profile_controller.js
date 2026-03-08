import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  toggleWeekendCap(event) {
    const capField = document.getElementById("weekend-cap-field")
    if (capField) {
      capField.classList.toggle("hidden", event.target.value !== "capped")
    }
  }
}
