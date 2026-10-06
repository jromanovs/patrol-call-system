import { Controller } from "@hotwired/stimulus"

// One pmtiles reader per page session keeps what it has read of the map file.
let protocol

// DSP-05, DSP-02, DYN-12: the map of Latvia from the system's own map file,
// with a marker for every site listed in the page, and one for every tracked
// car at its newest position (TRK-03). MapLibre GL and pmtiles
// load only here, so other pages never download them. A refresh of the page
// keeps the map and brings the markers up to date.
export default class extends Controller {
  static targets = [ "canvas", "site", "car" ]
  static values = {
    tiles: String, pmtiles: String, attribution: String, center: Array, zoom: Number, open: String,
    interactive: { type: Boolean, default: true }
  }

  async connect() {
    // A disconnect, or a disconnect and a new connect, while the libraries
    // load leaves this connect without a map to draw.
    const visit = this.visit = Symbol("visit")
    this.markers = new Map()
    this.cars = new Map()
    this.sync = this.sync.bind(this)
    this.show = this.show.bind(this)
    const [ maplibregl, { style, dark }, pmtiles ] =
      await Promise.all([ import("maplibre-gl"), import("map/style"), this.loadPmtiles() ])
    if (this.visit !== visit) return

    this.maplibregl = maplibregl
    protocol ??= new pmtiles.Protocol()
    maplibregl.addProtocol("pmtiles", protocol.tile)
    const tiles = new URL(this.tilesValue, document.baseURI)
    // USR-09: the map in the colours of the page's theme, drawn again when
    // the device that the page follows turns dark or light.
    this.device = window.matchMedia("(prefers-color-scheme: dark)")
    const drawn = () => {
      const theme = dark(document.documentElement.dataset.theme, this.device.matches) ? "dark" : "light"
      return style(`pmtiles://${tiles}`, this.attributionValue, theme)
    }
    this.recolour = () => this.map?.setStyle(drawn())
    this.map = new maplibregl.Map({
      container: this.canvasTarget,
      style: drawn(),
      center: this.centerValue,
      zoom: this.zoomValue,
      minZoom: 6,
      maxZoom: 18,
      maxBounds: [ [ 19.5, 55.0 ], [ 29.5, 58.6 ] ],
      interactive: this.interactiveValue,
      attributionControl: { compact: false }
    })
    if (this.interactiveValue) {
      this.map.addControl(new maplibregl.NavigationControl({ showCompass: false }), "bottom-right")
    }
    this.sync()
    this.markers.get(this.openValue)?.togglePopup()
    document.addEventListener("turbo:morph", this.sync)
    window.addEventListener("board:show", this.show)
    this.device.addEventListener("change", this.recolour)
  }

  disconnect() {
    this.visit = null
    document.removeEventListener("turbo:morph", this.sync)
    window.removeEventListener("board:show", this.show)
    this.device?.removeEventListener("change", this.recolour)
    this.map?.remove()
    this.map = null
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

    const tracked = new Set(this.carTargets.map((car) => car.id))
    for (const [ id, marker ] of this.cars) {
      if (!tracked.has(id)) {
        marker.remove()
        this.cars.delete(id)
      }
    }
    for (const car of this.carTargets) this.place(this.cars.get(car.id) ?? this.addCar(car), car)
  }

  // TRK-03: a car's mark shows its call sign; its name says its status and
  // how old its position is.
  addCar(car) {
    const element = document.createElement("div")
    element.className = "car-marker"
    element.setAttribute("role", "img")
    const marker = new this.maplibregl.Marker({ element })
    marker.setLngLat([ Number(car.dataset.longitude), Number(car.dataset.latitude) ]).addTo(this.map)
    this.cars.set(car.id, marker)
    return marker
  }

  place(marker, car) {
    const { latitude, longitude, sign, status, label } = car.dataset
    const element = marker.getElement()
    marker.setLngLat([ Number(longitude), Number(latitude) ])
    element.textContent = sign
    element.dataset.status = status
    element.setAttribute("aria-label", label)
  }

  add(site) {
    const button = document.createElement("button")
    button.type = "button"
    button.className = "map-marker"
    const popup = new this.maplibregl.Popup({ offset: 14, maxWidth: "min(20rem, 80vw)" })
    const marker = new this.maplibregl.Marker({ element: button }).setPopup(popup)
    marker.setLngLat([ Number(site.dataset.longitude), Number(site.dataset.latitude) ]).addTo(this.map)
    this.markers.set(site.id, marker)
    // DSP-03: the board marks the calls of the site picked here.
    button.addEventListener("click", () => this.dispatch("picked", { detail: { site: site.id } }))
    return marker
  }

  // DSP-03: a site chosen on the board, brought into view with its details.
  show({ detail: { site } }) {
    const marker = this.markers.get(site)
    if (!marker) return

    this.map.flyTo({ center: marker.getLngLat(), zoom: Math.max(this.map.getZoom(), 15) })
    for (const other of this.markers.values()) {
      if (other !== marker && other.getPopup().isOpen()) other.togglePopup()
    }
    if (!marker.getPopup().isOpen()) marker.togglePopup()
  }

  draw(marker, site) {
    const { latitude, longitude, priority, letter, label, arrival, kind } = site.dataset
    const button = marker.getElement()
    marker.setLngLat([ Number(longitude), Number(latitude) ])
    button.dataset.priority = priority
    // BR-21: the place of a crew's SOS is a mark of its own shape.
    if (kind) button.dataset.kind = kind
    if (arrival) button.dataset.arrival = arrival
    else delete button.dataset.arrival
    button.textContent = letter ?? ""
    button.setAttribute("aria-label", label)
    // New details only when they changed. Setting the content of an open
    // popup would move the focus, and on a phone the page, into it; there
    // the details are swapped in place.
    const details = site.firstElementChild
    if (marker.details === details.outerHTML) return

    marker.details = details.outerHTML
    const popup = marker.getPopup()
    const shown = popup.isOpen() && popup.getElement().querySelector(".map-popup")
    if (shown) shown.replaceWith(details.cloneNode(true))
    else popup.setDOMContent(details.cloneNode(true))
  }
}
