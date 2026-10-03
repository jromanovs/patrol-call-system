import { Controller } from "@hotwired/stimulus"

// CRW-07: Arrived and Close carry where this phone is. The step waits at
// most 10 seconds for the position; without permission, without a position
// or in a browser without positions it goes all the same, and its place is
// kept as unknown. An SOS (ADD-12) waits less and takes a position the
// phone already has, up to the age it names.
export default class extends Controller {
  static targets = ["latitude", "longitude", "accuracy"]
  static values = { wait: { type: Number, default: 10_000 }, age: { type: Number, default: 0 } }

  locate(event) {
    if (this.located || !("geolocation" in navigator)) return
    event.preventDefault()
    // A second tap while the phone looks for its position sends nothing twice.
    if (this.locating) return
    this.locating = true
    let sent = false
    const send = () => {
      if (sent) return
      sent = true
      clearTimeout(timer)
      this.located = true
      // With the tapped button, which Turbo disables until the answer comes.
      this.element.requestSubmit(event.submitter)
    }
    // The browser does not count the time its permission question stays open.
    const timer = setTimeout(send, this.waitValue)
    navigator.geolocation.getCurrentPosition(
      ({ coords }) => {
        if (sent) return
        this.latitudeTarget.value = coords.latitude
        this.longitudeTarget.value = coords.longitude
        this.accuracyTarget.value = Math.round(coords.accuracy)
        send()
      },
      send,
      { enableHighAccuracy: true, timeout: this.waitValue, maximumAge: this.ageValue }
    )
  }

  // A step that did not go through asks for the position again next time.
  reset() {
    this.located = false
    this.locating = false
  }
}
