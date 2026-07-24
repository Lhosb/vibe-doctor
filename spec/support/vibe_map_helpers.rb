module VibeMapHelpers
  # ECharts' SVG renderer does not expose any custom identifying attribute on
  # rendered points (confirmed via a live spike: neither a `name` nor an `id`
  # field returned from a data item survives to the DOM). This walks the
  # rendered <path> elements and matches the one whose parsed center is
  # closest to the pixel position ECharts itself reports for the given
  # (valence, arousal), then stamps a `data-album-id` attribute onto it so
  # Capybara has something to select. Real mood-vector coordinates are
  # continuous floats, so two distinct albums landing on the exact same
  # pixel is not a realistic collision risk.
  #
  # On this ECharts build, a scatter point's circle is drawn as a small
  # unit-scale arc positioned via a `transform="matrix(a,b,c,d,e,f)"` on the
  # <path> itself, rather than baking the final pixel center into `d` --
  # so the local center parsed from `d` must be run through that matrix.
  STAMP_JS = <<~JS
    (function(albumId, valence, arousal) {
      var container = document.querySelector('[data-library-vibe-map-target="map"]')
      var chart = container.__echartsInstance
      var svg = container.querySelector('svg')
      var pattern = /^M(-?[\\d.]+) (-?[\\d.]+)A(-?[\\d.]+) -?[\\d.]+ 0 1 1 -?[\\d.]+ -?[\\d.]+$/
      var target = chart.convertToPixel({ xAxisIndex: 0, yAxisIndex: 0 }, [ valence, arousal ])
      var candidates = Array.from(svg.querySelectorAll('path')).filter(function(el) {
        return pattern.test(el.getAttribute('d') || '')
      })
      var best = null
      var bestDist = Infinity
      candidates.forEach(function(el) {
        var match = el.getAttribute('d').match(pattern)
        var r = parseFloat(match[3])
        var localX = parseFloat(match[1]) - r
        var localY = parseFloat(match[2])
        var ex = localX
        var ey = localY
        var transform = el.getAttribute('transform')
        var m = transform && transform.match(/matrix\\(([^,]+),([^,]+),([^,]+),([^,]+),([^,]+),([^,)]+)\\)/)
        if (m) {
          var a = parseFloat(m[1]), b = parseFloat(m[2]), c = parseFloat(m[3])
          var d = parseFloat(m[4]), e = parseFloat(m[5]), f = parseFloat(m[6])
          ex = a * localX + c * localY + e
          ey = b * localX + d * localY + f
        }
        var dist = Math.hypot(ex - target[0], ey - target[1])
        if (dist < bestDist) { bestDist = dist; best = el }
      })
      if (best && bestDist < 2) best.setAttribute('data-album-id', String(albumId))
    })
  JS

  def find_vibe_map_point(album, valence:, arousal:)
    page.execute_script("(#{STAMP_JS})(arguments[0], arguments[1], arguments[2])", album.id, valence, arousal)
    find("[data-album-id='#{album.id}']")
  end
end

RSpec.configure do |config|
  config.include VibeMapHelpers, type: :system
end
