import { Controller } from "@hotwired/stimulus"

const DRAG_THRESHOLD_PX = 4

export default class extends Controller {
  static targets = ["map"]
  static values = {
    valenceMin: Number,
    valenceMax: Number,
    arousalMin: Number,
    arousalMax: Number
  }

  connect() {
    this.boundMouseMove = this.onMouseMove.bind(this)
    this.boundMouseUp = this.onMouseUp.bind(this)
  }

  dotMouseDown(event) {
    const dot = event.currentTarget
    this.dragging = {
      dot,
      moved: false,
      startX: event.clientX,
      startY: event.clientY,
      href: dot.dataset.href,
      albumId: dot.dataset.albumId,
      genre: dot.dataset.genre,
      danceability: dot.dataset.danceability,
      moodAcoustic: dot.dataset.moodAcoustic,
      moodRelaxed: dot.dataset.moodRelaxed,
      moodHappy: dot.dataset.moodHappy,
      valence: null,
      arousal: null
    }
    document.addEventListener("mousemove", this.boundMouseMove)
    document.addEventListener("mouseup", this.boundMouseUp)
    event.preventDefault()
  }

  onMouseMove(event) {
    if (!this.dragging) return

    const dx = event.clientX - this.dragging.startX
    const dy = event.clientY - this.dragging.startY
    if (!this.dragging.moved && Math.hypot(dx, dy) > DRAG_THRESHOLD_PX) {
      this.dragging.moved = true
    }
    if (!this.dragging.moved) return

    const bounds = this.mapTarget.getBoundingClientRect()
    const x = Math.min(Math.max((event.clientX - bounds.left) / bounds.width, 0), 1)
    const y = Math.min(Math.max((event.clientY - bounds.top) / bounds.height, 0), 1)

    this.dragging.dot.style.left = `${x * 100}%`
    this.dragging.dot.style.top = `${y * 100}%`
    this.dragging.valence = this.invert(x, this.valenceMinValue, this.valenceMaxValue)
    this.dragging.arousal = this.invert(1 - y, this.arousalMinValue, this.arousalMaxValue)
  }

  invert(displayFraction, min, max) {
    if (min === max) return displayFraction

    const value = min + displayFraction * (max - min)
    return Math.min(Math.max(value, 0), 1)
  }

  onMouseUp() {
    document.removeEventListener("mousemove", this.boundMouseMove)
    document.removeEventListener("mouseup", this.boundMouseUp)

    const state = this.dragging
    this.dragging = null
    if (!state) return

    if (state.moved) {
      this.saveOverride(state)
    } else {
      Turbo.visit(state.href)
    }
  }

  saveOverride(state) {
    const formData = new FormData()
    formData.append("valence", state.valence)
    formData.append("arousal", state.arousal)
    formData.append("danceability", state.danceability)
    formData.append("mood_acoustic", state.moodAcoustic)
    formData.append("mood_relaxed", state.moodRelaxed)
    formData.append("mood_happy", state.moodHappy)
    formData.append("genre", state.genre || "")
    formData.append("source", "vibe_map")

    const headers = {}
    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content
    if (csrfToken) headers["X-CSRF-Token"] = csrfToken

    fetch(`/albums/${state.albumId}/vibe_override`, {
      method: "POST",
      headers,
      body: formData
    }).then((response) => {
      if (response.ok) state.dot.classList.add("vibe-map-dot--saved")
    })
  }
}
