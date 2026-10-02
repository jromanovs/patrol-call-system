import { Controller } from "@hotwired/stimulus"

// One pmtiles reader per page session keeps what it has read of the map file.
let protocol

// DSP-05, DSP-02, DYN-12: the map of Latvia from the system's own map file,
// with a marker for every site listed in the page. MapLibre GL and pmtiles
// load only here, so other pages never download them. A refresh of the page
// keeps the map and brings the markers up to date.
export default class extends Controller {
  static targets = [ "canvas", "site" ]
  static values = {
    tiles: String, pmtiles: String, attribution: String, center: Array, zoom: Number, open: String,
    interactive: { type: Boolean, default: true }
  }

  async connect() {
    this.markers = new Map()
    this.sync = this.sync.bind(this)
    const [ maplibregl, { style }, pmtiles ] =
      await Promise.all([ import("maplibre-gl"), import("map/style"), this.loadPmtiles() ])
    if (!this.element.isConnected) return

    this.maplibregl = maplibregl
    protocol ??= new pmtiles.Protocol()
    maplibregl.addProtocol("pmtiles", protocol.tile)
    const tiles = new URL(this.tilesValue, document.baseURI)
    this.map = new maplibregl.Map({
      container: this.canvasTarget,
      style: style(`pmtiles://${tiles}`, this.attributionValue),
      center: this.centerValue,
      zoom: this.zoomValue,
      minZoom: 6,
      maxZoom: 18,
      maxBounds: [ [ 19.5, 55.0 ], [ 29.5, 58.6 ] ],
      interactive: this.interactiveValue,
      attributionControl: { compact: false }
    })
    if (this.interactiveValue) {
      this.map.addControl(new maplibregl.NavigationControl({ showCompass: false }), "top-right")
    }
    this.sync()
    this.markers.get(this.openValue)?.togglePopup()
    document.addEventListener("turbo:morph", this.sync)
  }

  disconnect() {
    document.removeEventListener("turbo:morph", this.sync)
    this.map?.remove()
  }

  // The browser build of pmtiles is a classic script, loaded once per page.
  loadPmtiles() {
    if (window.pmtiles) return Promise.resolve(window.pmtiles)

    return new Promise((resolve, reject) => {
      const script = document.createElement("script")
      script.src = this.pmtilesValue
      script.onload = () => resolve(window.pmtiles)
      script.onerror = reject
      document.head.append(script)
    })
  }

  // One marker for every site in the page: new ones are added, changed ones
  // redrawn, and the ones no longer listed removed.
  sync() {
    if (!this.map) return

    const listed = new Set(this.siteTargets.map((site) => site.id))
    for (const [ id, marker ] of this.markers) {
      if (!listed.has(id)) {
        marker.remove()
        this.markers.delete(id)
      }
    }
    for (const site of this.siteTargets) this.draw(this.markers.get(site.id) ?? this.add(site), site)
  }

  add(site) {
    const button = document.createElement("button")
    button.type = "button"
    button.className = "map-marker"
    const popup = new this.maplibregl.Popup({ offset: 14, maxWidth: "20rem" })
    const marker = new this.maplibregl.Marker({ element: button }).setPopup(popup)
    marker.setLngLat([ Number(site.dataset.longitude), Number(site.dataset.latitude) ]).addTo(this.map)
    this.markers.set(site.id, marker)
    return marker
  }

  draw(marker, site) {
    const { latitude, longitude, priority, letter, label } = site.dataset
    const button = marker.getElement()
    marker.setLngLat([ Number(longitude), Number(latitude) ])
    button.dataset.priority = priority
    button.textContent = letter ?? ""
    button.setAttribute("aria-label", label)
    marker.getPopup().setDOMContent(site.firstElementChild.cloneNode(true))
  }
}
