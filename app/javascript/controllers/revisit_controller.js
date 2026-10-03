import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

// DYN-15: a screen that comes back into view — the phone unlocked, the app
// opened again or a notice tapped — asks for its current state, since the
// live updates sent while it was out of view are not sent again. The refresh
// is a morph, so the screen keeps its place and what the page keeps.
export default class extends Controller {
  refresh() {
    if (document.visibilityState === "visible") Turbo.visit(window.location.href, { action: "replace" })
  }
}
