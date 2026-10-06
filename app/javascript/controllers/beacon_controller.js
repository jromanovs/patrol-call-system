import { Controller } from "@hotwired/stimulus"

// TRK-04: the crew's phone as the position source of its car. While the crew
// screen is open and in front, the phone's position is sent at once, when the
// screen comes back in front, and at every interval; the screen says that it
// is sent and when, or that the phone gives none. A browser sends nothing
// while the phone is locked. A refresh of the screen in place brings the
// server's blank block back, so what was shown is put back; a refresh without
// the block ends the sending. What is read out comes from the page, in the
// language of the page.
export default class extends Controller {
  static targets = ["on", "off", "time", "status"]
  static values = { url: String, interval: Number, sendingText: String, silentText: String }

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
      // The car's source is no longer this phone: nothing more is sent or said.
      if (response.status === 409) return this.element.remove()
      // Sent means kept by the server: not an answer on the way to a sign-in page.
      if (response.status !== 204 || response.redirected) return

      this.sentAt =
        new Date().toLocaleTimeString("lv-LV", { hour: "2-digit", minute: "2-digit", timeZone: "Europe/Riga" })
      this.show(true)
    } catch {
      // No connection: the next position is sent in its turn.
    }
  }

  // A change of state is read out; a position sent again is not.
  show(sending) {
    if (sending !== this.sending) {
      this.statusTarget.textContent = sending ? this.sendingTextValue : this.silentTextValue
    }
    this.sending = sending
    this.restore()
  }

  restore() {
    if (this.sending === undefined) return

    this.onTarget.hidden = !this.sending
    this.offTarget.hidden = this.sending
    if (this.sentAt) this.timeTarget.textContent = this.sentAt
  }
}
