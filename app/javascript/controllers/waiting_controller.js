import { Controller } from "@hotwired/stimulus"

// DYN-03: the waiting time of every active call on the board, the minutes
// since its car was dispatched, and its handling time in the call list are
// recounted once a minute in the browser, without asking the server; each
// counts from the time in its data-received-at.
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
