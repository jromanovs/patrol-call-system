import { Controller } from "@hotwired/stimulus"

// DYN-03: the waiting time of every active call on the board, the minutes
// since its car was dispatched, and its handling time in the call list are
// recounted once a minute in the browser, without asking the server; each
// counts from the time in its data-received-at. Only the number is put anew:
// the words around it stay as the server wrote them, in the language of the
// page.
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
      // A phone clock a little ahead never makes the minutes run below zero.
      const minutes = Math.max(0, Math.floor((now - Date.parse(cell.dataset.receivedAt)) / 60_000))
      cell.textContent = cell.textContent.replace(/\d+/, minutes)
    }
  }
}
