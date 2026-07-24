import { Controller } from "@hotwired/stimulus"
import * as echarts from "echarts"

const DRAG_THRESHOLD_PX = 4

export default class extends Controller {
  static targets = ["map"]
  static values = { dots: Array }

  connect() {
    this.genres = [ ...new Set(this.dotsValue.map((dot) => dot.genre)) ]
    this.chart = echarts.init(this.mapTarget, null, { renderer: "svg" })
    this.chart.setOption(this.buildOption())

    // Stashed purely for system-spec introspection (see spec/support/vibe_map_helpers.rb) --
    // production code never reads this back.
    this.mapTarget.__echartsInstance = this.chart

    this.chart.on("mousedown", (params) => this.onChartMouseDown(params))
    this.chart.on("click", (params) => this.onChartClick(params))
  }

  disconnect() {
    this.chart.dispose()
  }

  buildOption() {
    return {
      // `scale: true` is required: without it, ECharts' default numeric axis
      // forces the range to include 0 with no padding, which would bunch
      // real mood data into a corner -- exactly the problem this feature
      // exists to fix. With it, multiple points stretch to fill the full
      // range, and a single point still gets a sane, non-degenerate range
      // (confirmed via a live spike).
      xAxis: { scale: true, name: "Sad ↔ Happy", nameLocation: "middle", nameGap: 28 },
      yAxis: { scale: true, name: "Calm ↔ Energetic", nameLocation: "middle", nameGap: 32 },
      grid: { left: 48, right: 24, top: 24, bottom: 56 },
      legend: { data: this.genres, bottom: 8 },
      tooltip: {
        trigger: "item",
        formatter: (params) => params.data.dot.phrase
      },
      series: this.genres.map((genre) => ({
        name: genre,
        type: "scatter",
        symbolSize: 12,
        data: this.dotsValue
          .filter((dot) => dot.genre === genre)
          .map((dot) => ({ value: [ dot.valence, dot.arousal ], dot })),
        label: {
          show: true,
          position: "right",
          formatter: (params) => params.data.dot.title
        },
        labelLayout: { hideOverlap: true }
      }))
    }
  }

  onChartMouseDown(params) {
    if (params.componentType !== "series") return

    this.dragging = {
      dot: params.data.dot,
      moved: false,
      startX: params.event.event.clientX,
      startY: params.event.event.clientY
    }
    this.boundMove = this.onDocumentMouseMove.bind(this)
    this.boundUp = this.onDocumentMouseUp.bind(this)
    document.addEventListener("mousemove", this.boundMove)
    document.addEventListener("mouseup", this.boundUp)
  }

  onDocumentMouseMove(event) {
    if (!this.dragging) return

    const dx = event.clientX - this.dragging.startX
    const dy = event.clientY - this.dragging.startY
    if (!this.dragging.moved && Math.hypot(dx, dy) > DRAG_THRESHOLD_PX) {
      this.dragging.moved = true
    }
  }

  onDocumentMouseUp(event) {
    document.removeEventListener("mousemove", this.boundMove)
    document.removeEventListener("mouseup", this.boundUp)

    const state = this.dragging
    this.dragging = null
    if (!state || !state.moved) return

    this.suppressNextClick = true

    const bounds = this.mapTarget.getBoundingClientRect()
    const px = event.clientX - bounds.left
    const py = event.clientY - bounds.top
    const [ valence, arousal ] = this.chart.convertFromPixel({ xAxisIndex: 0, yAxisIndex: 0 }, [ px, py ])

    this.saveOverride(state.dot, this.clamp01(valence), this.clamp01(arousal))
  }

  onChartClick(params) {
    if (this.suppressNextClick) {
      this.suppressNextClick = false
      return
    }
    if (params.componentType !== "series") return

    Turbo.visit(params.data.dot.href)
  }

  clamp01(value) {
    return Math.min(Math.max(value, 0), 1)
  }

  saveOverride(dot, valence, arousal) {
    const formData = new FormData()
    formData.append("valence", valence)
    formData.append("arousal", arousal)
    formData.append("danceability", dot.danceability)
    formData.append("mood_acoustic", dot.mood_acoustic)
    formData.append("mood_relaxed", dot.mood_relaxed)
    formData.append("mood_happy", dot.mood_happy)
    formData.append("genre", dot.genre || "")
    formData.append("source", "vibe_map")

    const headers = {}
    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content
    if (csrfToken) headers["X-CSRF-Token"] = csrfToken

    fetch(`/albums/${dot.id}/vibe_override`, {
      method: "POST",
      headers,
      body: formData
    }).then((response) => {
      if (response.ok) this.mapTarget.setAttribute("data-saved-album-id", dot.id)
    })
  }
}
