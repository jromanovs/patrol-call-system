import { Controller } from "@hotwired/stimulus"

// DYN-11: while the dispatcher types, suggestions from the address register
// load under the field; choosing one fills the address of the site. Typing
// again clears the chosen address until another one is chosen.
export default class extends Controller {
  static targets = ["query", "value", "suggestions"]
  static values = { url: String }

  search() {
    this.valueTarget.value = ""
    clearTimeout(this.timer)
    this.timer = setTimeout(() => {
      const url = new URL(this.urlValue, window.location.href)
      url.searchParams.set("q", this.queryTarget.value)
      this.suggestionsTarget.src = url.toString()
    }, 300)
  }

  choose(event) {
    const { addressId, addressLabel } = event.currentTarget.dataset
    this.valueTarget.value = addressId
    this.queryTarget.value = addressLabel
    this.suggestionsTarget.removeAttribute("src")
    this.suggestionsTarget.replaceChildren()
    this.queryTarget.focus()
  }

  disconnect() {
    clearTimeout(this.timer)
  }
}
