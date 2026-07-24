import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["query", "genre", "submit", "result"];

  submit(event) {
    event.preventDefault();
    if (this.requestInFlight) return;

    const query = this.queryTarget.value;
    const genre = this.genreTarget.value.trim();

    const formData = new FormData();
    formData.append("query", query);
    if (genre !== "") formData.append("genre", genre);

    const headers = {};
    const csrfToken = document.querySelector(
      'meta[name="csrf-token"]',
    )?.content;
    if (csrfToken) headers["X-CSRF-Token"] = csrfToken;

    this.requestInFlight = true;
    this.submitTarget.disabled = true;

    fetch("/recommend", { method: "POST", headers, body: formData })
      .then((response) => response.json().then((body) => ({ ok: response.ok, body })))
      .then(({ ok, body }) => {
        if (ok) this.renderResult(body);
      })
      .finally(() => {
        this.requestInFlight = false;
        this.submitTarget.disabled = false;
      });
  }

  renderResult({ album, explanation, recommendation_event_id }) {
    this.resultTarget.textContent = "";

    const wrapper = document.createElement("div");
    wrapper.className = "p-4 border border-gray-200 rounded-lg bg-gray-50";

    const title = document.createElement("h2");
    title.className = "text-lg font-semibold";
    title.textContent = album.title;

    const artists = document.createElement("p");
    artists.className = "text-gray-600";
    artists.textContent = album.artists.join(", ");

    const explanationEl = document.createElement("p");
    explanationEl.className = "mt-2 text-gray-800";
    explanationEl.textContent = explanation;

    const links = document.createElement("div");
    links.className = "mt-4 flex gap-4";

    const albumLink = document.createElement("a");
    albumLink.href = `/albums/${album.id}`;
    albumLink.className = "text-blue-600 underline hover:no-underline";
    albumLink.textContent = "View album";

    const feedbackLink = document.createElement("a");
    feedbackLink.href = `/feedback?recommendation_event_id=${recommendation_event_id}`;
    feedbackLink.className = "text-blue-600 underline hover:no-underline";
    feedbackLink.textContent = "Give feedback";

    links.append(albumLink, feedbackLink);
    wrapper.append(title, artists, explanationEl, links);
    this.resultTarget.append(wrapper);
  }
}
