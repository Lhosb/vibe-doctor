import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { eventId: Number }

  choose(event) {
    const outcome = event.params.outcome
    const formData = new FormData()
    formData.append("recommendation_event_id", this.eventIdValue)
    formData.append("outcome", outcome)

    const headers = { Accept: "text/vnd.turbo-stream.html" }
    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content
    if (csrfToken) headers["X-CSRF-Token"] = csrfToken

    fetch("/feedback", {
      method: "POST",
      headers,
      body: formData
    })
      .then((response) => response.text())
      .then((html) => Turbo.renderStreamMessage(html))
  }
}
