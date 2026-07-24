import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["panel", "backdrop"]

  toggle() {
    this.panelTarget.classList.toggle("-translate-x-full")
    this.backdropTarget.classList.toggle("hidden")
  }

  close() {
    this.panelTarget.classList.add("-translate-x-full")
    this.backdropTarget.classList.add("hidden")
  }
}
