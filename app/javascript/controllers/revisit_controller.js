import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

// DYN-15: a screen that comes back into view — the phone unlocked, the app
// opened again or a notice tapped — asks for its current state, since the
// live updates sent while it was out of view are not sent again. The refresh
// is a morph, so the screen keeps its place and what the page keeps.
//
// A step still waiting for the server (Arrived, Close) is let finish: a
// refresh now would cancel it. Once answered, its own reply shows the
// state; a step that failed leaves the refresh to be done then.
export default class extends Controller {
  submitting = false
  due = false

  refresh() {
    if (document.visibilityState !== "visible") return
    if (this.submitting) {
      this.due = true
    } else {
      Turbo.visit(window.location.href, { action: "replace" })
    }
  }

  start() {
    this.submitting = true
  }

  finish(event) {
    this.submitting = false
    const due = this.due
    this.due = false
    if (due && !event.detail.success) this.refresh()
  }
}
