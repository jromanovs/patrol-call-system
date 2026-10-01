import { Controller } from "@hotwired/stimulus"

// DYN-03: the waiting time of every active call is recounted once a minute in
// the browser, without asking the server.
export default class extends Controller {
  static targets = ["minutes"]

  connect() {
    this.timer = setInterval(() => this.recount(), 60_000)
  }

  disconnect() {
    clearInterval(this.timer)
  }

  recount() {
    const now = Date.now()
    for (const cell of this.minutesTargets) {
      const minutes = Math.floor((now - Date.parse(cell.dataset.receivedAt)) / 60_000)
      cell.textContent = `${minutes} min`
    }
  }
}
