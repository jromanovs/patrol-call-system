import { Controller } from "@hotwired/stimulus"

// DSP-03: the panels of the main screen. Which panels are minimized, and in
// a narrow window the tab and whether the sheet is lowered, are kept on the
// <html> element, which a refresh of the page leaves alone, and in cookies,
// from which the server draws the next visit the same way.
const PANELS = [ "calls", "cars", "legend" ]
// In a narrow or low window the panels are one sheet, and the legend opens
// only on request (the $sheet media query of the stylesheets).
const NARROW = window.matchMedia("(max-width: 47.99rem), (max-height: 32rem)")

export default class extends Controller {
  static targets = [ "card" ]

  connect() {
    this.refresh = this.refresh.bind(this)
    NARROW.addEventListener("change", this.refresh)
    document.addEventListener("turbo:morph", this.refresh)
    this.refresh()
  }

  disconnect() {
    document.removeEventListener("turbo:morph", this.refresh)
    NARROW.removeEventListener("change", this.refresh)
  }

  toggle({ params: { panel } }) {
    if (panel === "legend" && NARROW.matches) {
      this.keep("legendPhone", this.chosen("legendPhone") === "open" ? null : "open")
    } else {
      const choice = `${panel}Panel`
      this.keep(choice, this.chosen(choice) === "minimized" ? null : "minimized")
    }
  }

  minimized(panel) {
    if (panel === "legend" && NARROW.matches) return this.chosen("legendPhone") !== "open"
    return this.chosen(`${panel}Panel`) === "minimized"
  }

  toggleSheet() {
    this.keep("sheet", this.chosen("sheet") === "lowered" ? null : "lowered")
  }

  showTab({ params: { tab } }) {
    this.keep("sheetTab", tab === "cars" ? "cars" : null)
    this.keep("sheet", null)
  }

  // A call's site, shown on the map with its details.
  show({ params: { site } }) {
    window.dispatchEvent(new CustomEvent("board:show", { detail: { site } }))
    this.mark({ detail: { site } })
  }

  // A site picked on the map shows its calls in the panel, opening it if the
  // user had minimized it, and marks them.
  mark({ detail: { site } }) {
    this.marked = site
    this.markCards()
    const card = this.cardTargets.find((target) => target.dataset.site === site)
    if (!card) return

    if (NARROW.matches) {
      this.keep("sheetTab", null)
      this.keep("sheet", null)
    } else {
      this.keep("callsPanel", null)
    }
    card.scrollIntoView({ block: "nearest" })
  }

  markCards() {
    for (const card of this.cardTargets) card.classList.toggle("marked", card.dataset.site === this.marked)
  }

  chosen(choice) {
    return document.documentElement.dataset[choice]
  }

  // For a year, the cookie named as BoardHelper reads it.
  keep(choice, value) {
    if (value) document.documentElement.dataset[choice] = value
    else delete document.documentElement.dataset[choice]
    const secure = location.protocol === "https:" ? "; secure" : ""
    document.cookie = `board_${choice}=${value ?? ""}; path=/; max-age=${value ? 31536000 : 0}; samesite=lax${secure}`
    this.refresh()
  }

  // The buttons tell the state of what they control, also after a refresh of
  // the page has put back their markup.
  refresh() {
    for (const panel of PANELS) {
      const button = this.element.querySelector(`.panel-toggle[aria-controls="${panel}-body"]`)
      button?.setAttribute("aria-expanded", String(!this.minimized(panel)))
    }
    const cars = this.chosen("sheetTab") === "cars"
    for (const tab of this.element.querySelectorAll(".sheet-tabs [role=tab]")) {
      tab.setAttribute("aria-selected", String(tab.getAttribute("aria-controls") === (cars ? "cars-panel" : "calls-panel")))
    }
    this.element.querySelector(".sheet-handle")?.setAttribute("aria-expanded", String(this.chosen("sheet") !== "lowered"))
    this.markCards()
  }
}
