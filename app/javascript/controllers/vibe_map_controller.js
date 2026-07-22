import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["marker"]
  static values = { albumId: Number, genre: String }

  place(event) {
    const bounds = this.element.getBoundingClientRect()
    const x = (event.clientX - bounds.left) / bounds.width
    const y = (event.clientY - bounds.top) / bounds.height

    const valence = x
    const arousal = 1 - y

    this.markerTarget.style.left = `${x * 100}%`
    this.markerTarget.style.top = `${y * 100}%`

    const formData = new FormData()
    formData.append("valence", valence)
    formData.append("arousal", arousal)
    formData.append("danceability", 0.5)
    formData.append("mood_acoustic", 0.5)
    formData.append("mood_relaxed", 0.5)
    formData.append("mood_happy", 0.5)
    formData.append("genre", this.genreValue || "")
    formData.append("source", "vibe_map")

    const headers = {}
    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content
    if (csrfToken) headers["X-CSRF-Token"] = csrfToken

    fetch(`/albums/${this.albumIdValue}/vibe_override`, {
      method: "POST",
      headers,
      body: formData
    }).then((response) => {
      if (response.ok) this.element.classList.add("vibe-map--saved")
    })
  }
}
