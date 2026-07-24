import { Controller } from "@hotwired/stimulus";
import * as echarts from "echarts";

const DRAG_THRESHOLD_PX = 4;

export default class extends Controller {
  static targets = ["map"];
  static values = { dots: Array };

  connect() {
    this.genres = [...new Set(this.dotsValue.map((dot) => dot.genre))];
    this.chart = echarts.init(this.mapTarget, null, { renderer: "svg" });
    this.chart.setOption(this.buildOption());

    // Stashed purely for system-spec introspection (see spec/support/vibe_map_helpers.rb) --
    // production code never reads this back.
    this.mapTarget.__echartsInstance = this.chart;

    this.chart.on("mousedown", (params) => this.onChartMouseDown(params));
    this.chart.on("click", (params) => this.onChartClick(params));
  }

  disconnect() {
    this.chart.dispose();
  }

  buildOption() {
    return {
      // Disabled: with the default entry animation, a point's final on-screen
      // position isn't settled until the animation completes, so a click or
      // drag that starts immediately after render can land at a stale
      // position (confirmed via a live spike -- this caused an intermittent
      // "click misses the point entirely" failure).
      animation: false,
      // `scale: true` is required: without it, ECharts' default numeric axis
      // forces the range to include 0 with no padding, which would bunch
      // real mood data into a corner -- exactly the problem this feature
      // exists to fix. With it, multiple points stretch to fill the full
      // range, and a single point still gets a sane, non-degenerate range
      // (confirmed via a live spike).
      // No xAxis/yAxis `name` here: the surrounding view (SAD/HAPPY/CALM/
      // ENERGETIC captions) already labels each axis's direction, so an
      // ECharts-drawn axis name would just duplicate that text and crowd the
      // legend/tick-label space.
      xAxis: { scale: true },
      yAxis: { scale: true },
      // `containLabel: true` lets ECharts grow the grid to fit whatever tick
      // labels actually render, instead of hand-tuned left/right/bottom
      // offsets that only happen to fit today's label widths. Left/top/bottom
      // are small fixed starting insets (not fit-to-content ones): ECharts
      // defaults any unset side to 10% of the container, which -- stacked on
      // top of containLabel's own padding -- left far more empty margin than
      // the tick labels actually need. `bottom` stays larger than left/top
      // purely to clear the legend row below (a fixed-height row, not
      // something that scales with the container).
      grid: { left: 8, top: 16, bottom: 48, containLabel: true },
      legend: {
        data: this.genres,
        type: "scroll",
        selector: [
          {
            type: "all",
            title: "All",
          },
        ],
      },
      dataZoom: [
        { type: "inside", xAxisIndex: 0 },
        { type: "inside", yAxisIndex: 0 },
      ],
      tooltip: {
        trigger: "item",
        formatter: (params) => params.data.dot.phrase,
      },
      series: this.genres.map((genre) => ({
        name: genre,
        type: "scatter",
        symbolSize: 12,
        data: this.dotsValue
          .filter((dot) => dot.genre === genre)
          .map((dot) => ({ value: [dot.valence, dot.arousal], dot })),
        label: {
          show: true,
          position: "right",
          formatter: (params) => params.data.dot.title,
        },
        labelLayout: { hideOverlap: true },
      })),
    };
  }

  onChartMouseDown(params) {
    if (params.componentType !== "series") return;

    this.dragging = {
      dot: params.data.dot,
      moved: false,
      startX: params.event.event.clientX,
      startY: params.event.event.clientY,
    };
    // Registered on the capture phase: with dataZoom's "inside" roam active,
    // its own internal drag tracking can stop these events from ever
    // reaching bubble-phase document listeners (confirmed via a live spike).
    // Capture-phase listeners at document run first regardless, so this
    // guarantees our own drag tracking still sees every move/up.
    this.boundMove = this.onDocumentMouseMove.bind(this);
    this.boundUp = this.onDocumentMouseUp.bind(this);
    document.addEventListener("mousemove", this.boundMove, true);
    document.addEventListener("mouseup", this.boundUp, true);
  }

  onDocumentMouseMove(event) {
    if (!this.dragging) return;

    const dx = event.clientX - this.dragging.startX;
    const dy = event.clientY - this.dragging.startY;
    if (!this.dragging.moved && Math.hypot(dx, dy) > DRAG_THRESHOLD_PX) {
      this.dragging.moved = true;

      // Disabling dataZoom must wait until a real drag is confirmed (not on
      // every mousedown): calling chart.setOption -- even for this unrelated
      // option -- resets ECharts' internal pending-click gesture tracking, so
      // doing it unconditionally on mousedown silently swallows plain clicks
      // (confirmed via a live spike: chart.on("click", ...) never fires at
      // all afterward). Deferring it to here means a plain click never
      // touches setOption at all.
      this.chart.setOption({
        dataZoom: [
          { type: "inside", xAxisIndex: 0, disabled: true },
          { type: "inside", yAxisIndex: 0, disabled: true },
        ],
      });
    }
  }

  onDocumentMouseUp(event) {
    document.removeEventListener("mousemove", this.boundMove, true);
    document.removeEventListener("mouseup", this.boundUp, true);

    const state = this.dragging;
    this.dragging = null;
    if (!state || !state.moved) return;

    this.chart.setOption({
      dataZoom: [
        { type: "inside", xAxisIndex: 0, disabled: false },
        { type: "inside", yAxisIndex: 0, disabled: false },
      ],
    });

    this.suppressNextClick = true;

    const bounds = this.mapTarget.getBoundingClientRect();
    const px = event.clientX - bounds.left;
    const py = event.clientY - bounds.top;
    const [valence, arousal] = this.chart.convertFromPixel(
      { xAxisIndex: 0, yAxisIndex: 0 },
      [px, py],
    );

    this.saveOverride(state.dot, this.clamp01(valence), this.clamp01(arousal));
  }

  onChartClick(params) {
    if (this.suppressNextClick) {
      this.suppressNextClick = false;
      return;
    }
    if (params.componentType !== "series") return;

    Turbo.visit(params.data.dot.href);
  }

  clamp01(value) {
    return Math.min(Math.max(value, 0), 1);
  }

  saveOverride(dot, valence, arousal) {
    const formData = new FormData();
    formData.append("valence", valence);
    formData.append("arousal", arousal);
    formData.append("danceability", dot.danceability);
    formData.append("mood_acoustic", dot.mood_acoustic);
    formData.append("mood_relaxed", dot.mood_relaxed);
    formData.append("mood_happy", dot.mood_happy);
    formData.append("genre", dot.genre || "");
    formData.append("source", "vibe_map");

    const headers = {};
    const csrfToken = document.querySelector(
      'meta[name="csrf-token"]',
    )?.content;
    if (csrfToken) headers["X-CSRF-Token"] = csrfToken;

    fetch(`/albums/${dot.id}/vibe_override`, {
      method: "POST",
      headers,
      body: formData,
    }).then((response) => {
      if (response.ok)
        this.mapTarget.setAttribute("data-saved-album-id", dot.id);
    });
  }
}
