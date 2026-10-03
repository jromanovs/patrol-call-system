import { Controller } from "@hotwired/stimulus"

// TRK-04: the crew's phone as the position source of its car. While the crew
// screen is open and in front, the phone's position is sent at once and then
// at every interval; the screen says that it is sent and when, or that the
// phone gives none. A browser sends nothing while the phone is locked.
export default class extends Controller {
  static targets = ["on", "off", "time"]
  static values = { url: String, interval: Number }

  connect() {
    if (!("geolocation" in navigator)) return this.show(false)

    this.send()
    this.timer = setInterval(() => this.send(), this.intervalValue)
  }

  disconnect() {
    clearInterval(this.timer)
  }

  send() {
    if (document.visibilityState !== "visible") return

    navigator.geolocation.getCurrentPosition(
      ({ coords }) => this.post(coords),
      () => this.show(false),
      { enableHighAccuracy: true, timeout: 10_000, maximumAge: 0 }
    )
  }

  async post({ latitude, longitude, accuracy }) {
    const token = document.querySelector("meta[name=csrf-token]")?.content
    try {
      const response = await fetch(this.urlValue, {
        method: "POST",
        headers: { "Content-Type": "application/json", "X-CSRF-Token": token },
        body: JSON.stringify({ latitude, longitude, accuracy })
      })
      // The car's source is no longer this phone: nothing more is sent.
      if (response.status === 409) return this.disconnect()
      if (!response.ok) return

      this.timeTarget.textContent =
        new Date().toLocaleTimeString("lv-LV", { hour: "2-digit", minute: "2-digit", timeZone: "Europe/Riga" })
      this.show(true)
    } catch {
      // No connection: the next position is sent in its turn.
    }
  }

  show(sending) {
    this.onTarget.hidden = !sending
    this.offTarget.hidden = sending
  }
}
