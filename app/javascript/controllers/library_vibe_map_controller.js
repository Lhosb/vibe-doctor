import { Controller } from "@hotwired/stimulus"
import * as echarts from "echarts"

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

  onChartClick(params) {
    if (params.componentType !== "series") return

    Turbo.visit(params.data.dot.href)
  }
}
