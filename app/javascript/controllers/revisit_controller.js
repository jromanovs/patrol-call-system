import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

// DYN-15: a screen that comes back into view — the phone unlocked, the app
// opened again or a notice tapped — asks for its current state, since the
// live updates sent while it was out of view are not sent again. The refresh
// is a morph, so the screen keeps its place and what the page keeps.
//
// A step still waiting for the server (Accept, Arrived, Close) is let finish: a
// refresh now would cancel it. Once answered, its own reply shows the
// state; a step that failed leaves the refresh to be done then.
//
// Without the network, or with the server out of reach, a refresh would put
// the browser's error page in place of the call; the screen keeps what it
// shows and tries again when the network is back, or a little later.
const RETRY = 15_000

export default class extends Controller {
  submitting = false
  due = false

  disconnect() {
    clearTimeout(this.timer)
  }

  async refresh() {
    if (document.visibilityState !== "visible") return
    this.due = true
    if (this.submitting) return
    if (!(await this.reachable())) {
      clearTimeout(this.timer)
      this.timer = setTimeout(() => this.retry(), RETRY)
      return
    }
    if (this.submitting || !this.due) return
    this.due = false
    Turbo.visit(window.location.href, { action: "replace" })
  }

  retry() {
    if (this.due) this.refresh()
  }

  start() {
    this.submitting = true
  }

  finish(event) {
    this.submitting = false
    if (event.detail.success) {
      this.due = false
    } else {
      this.retry()
    }
  }

  async reachable() {
    try {
      const response = await fetch(window.location.href, { method: "HEAD", cache: "no-store" })
      return response.ok
    } catch {
      return false
    }
  }
}
