import { Controller } from "@hotwired/stimulus"

// CRW-07: Arrived and Close carry where this phone is. The step waits at
// most 10 seconds for the position; without permission, without a position
// or in a browser without positions it goes all the same, and its place is
// kept as unknown.
export default class extends Controller {
  static targets = ["latitude", "longitude", "accuracy"]

  locate(event) {
    if (this.located || !("geolocation" in navigator)) return
    event.preventDefault()
    // A second tap while the phone looks for its position sends nothing twice.
    if (this.locating) return
    this.locating = true
    navigator.geolocation.getCurrentPosition(
      ({ coords }) => {
        this.latitudeTarget.value = coords.latitude
        this.longitudeTarget.value = coords.longitude
        this.accuracyTarget.value = Math.round(coords.accuracy)
        this.send()
      },
      () => this.send(),
      { enableHighAccuracy: true, timeout: 10_000, maximumAge: 30_000 }
    )
  }

  send() {
    this.located = true
    this.element.requestSubmit()
  }
}
