import { Controller } from "@hotwired/stimulus"

// DSP-03: the panels of the main screen. Which panels are minimized, and in
// a narrow window the tab and whether the sheet is lowered, are kept on the
// <html> element, which a refresh of the page leaves alone, and in the
// browser's storage for the next visit.
const PANELS = { calls: "active calls", cars: "patrol cars", legend: "legend" }
const CHOICES = [ "callsPanel", "carsPanel", "legendPanel", "legendPhone", "sheet", "sheetTab" ]
// Below this width the panels are one sheet, and the legend opens only on
// request (the $narrow of the stylesheets).
const NARROW = window.matchMedia("(max-width: 47.99rem)")

export default class extends Controller {
  static targets = [ "card" ]

  connect() {
    this.refresh = this.refresh.bind(this)
    NARROW.addEventListener("change", this.refresh)
    for (const choice of CHOICES) {
      const kept = this.stored(choice)
      if (kept) document.documentElement.dataset[choice] = kept
    }
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

  // A site picked on the map marks its calls in the panel.
  mark({ detail: { site } }) {
    this.marked = site
    this.markCards()
    this.cardTargets.find((card) => card.dataset.site === site)?.scrollIntoView({ block: "nearest" })
  }

  markCards() {
    for (const card of this.cardTargets) card.classList.toggle("marked", card.dataset.site === this.marked)
  }

  chosen(choice) {
    return document.documentElement.dataset[choice]
  }

  keep(choice, value) {
    if (value) document.documentElement.dataset[choice] = value
    else delete document.documentElement.dataset[choice]
    try {
      if (value) localStorage.setItem(`board.${choice}`, value)
      else localStorage.removeItem(`board.${choice}`)
    } catch {
      // Without storage the choice lasts until the page is left.
    }
    this.refresh()
  }

  stored(choice) {
    try {
      return localStorage.getItem(`board.${choice}`)
    } catch {
      return null
    }
  }

  // The buttons tell what they will do, also after a refresh of the page
  // has put back their markup.
  refresh() {
    for (const [ panel, name ] of Object.entries(PANELS)) {
      const button = this.element.querySelector(`.panel-toggle[aria-controls="${panel}-body"]`)
      if (!button) continue

      const minimized = this.minimized(panel)
      button.setAttribute("aria-expanded", String(!minimized))
      button.setAttribute("aria-label", `${minimized ? "Open" : "Minimize"} ${name}`)
    }
    const cars = this.chosen("sheetTab") === "cars"
    for (const tab of this.element.querySelectorAll(".sheet-tabs [role=tab]")) {
      tab.setAttribute("aria-selected", String(tab.getAttribute("aria-controls") === (cars ? "cars-panel" : "calls-panel")))
    }
    const handle = this.element.querySelector(".sheet-handle")
    const lowered = this.chosen("sheet") === "lowered"
    handle?.setAttribute("aria-expanded", String(!lowered))
    handle?.setAttribute("aria-label", lowered ? "Raise the panel" : "Lower the panel")
    this.markCards()
  }
}
