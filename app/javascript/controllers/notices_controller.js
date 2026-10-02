import { Controller } from "@hotwired/stimulus"

// CRW-04, CRW-05, DYN-16: turns the notices of the crew's car on and off for
// this phone, and says whether they are on, off, blocked or unavailable.
export default class extends Controller {
  static targets = ["state", "on", "off"]
  static values = { key: String, url: String, worker: String }

  async connect() {
    if (!("serviceWorker" in navigator && "PushManager" in window && "Notification" in window)) {
      return this.show("unavailable")
    }
    try {
      await navigator.serviceWorker.register(this.workerValue)
      this.registration = await navigator.serviceWorker.ready
      const subscription = await this.registration.pushManager.getSubscription()
      if (Notification.permission === "denied") return this.show("blocked")
      // The server may have forgotten the phone since; it keeps one record of it.
      if (subscription) await this.keep(subscription)
      this.show(subscription ? "on" : "off")
    } catch {
      this.show("unavailable")
    }
  }

  // An iPhone asks for the permission only straight after a tap, so the
  // subscription is the first thing done here.
  async turnOn() {
    try {
      const subscription = await this.registration.pushManager.subscribe({
        userVisibleOnly: true,
        applicationServerKey: this.applicationServerKey
      })
      await this.keep(subscription)
      this.show("on")
    } catch {
      this.show(Notification.permission === "denied" ? "blocked" : "off")
    }
  }

  async turnOff() {
    try {
      const subscription = await this.registration.pushManager.getSubscription()
      if (subscription) {
        await this.send("DELETE", { endpoint: subscription.endpoint })
        await subscription.unsubscribe()
      }
      this.show("off")
    } catch {
      this.show("on")
    }
  }

  keep(subscription) {
    return this.send("POST", subscription.toJSON())
  }

  async send(method, body) {
    const response = await fetch(this.urlValue, {
      method,
      headers: {
        "Content-Type": "application/json",
        Accept: "application/json",
        "X-CSRF-Token": document.querySelector("meta[name=csrf-token]")?.content
      },
      body: JSON.stringify(body)
    })
    if (!response.ok) throw new Error(`The server answered ${response.status}`)
  }

  show(state) {
    for (const line of this.stateTargets) line.hidden = line.dataset.state !== state
    this.onTarget.hidden = state !== "off"
    this.offTarget.hidden = state !== "on"
  }

  // The server's public key, given in URL-safe Base64, as the bytes the
  // browser takes.
  get applicationServerKey() {
    const bytes = atob(this.keyValue.replaceAll("-", "+").replaceAll("_", "/"))
    return Uint8Array.from(bytes, (character) => character.charCodeAt(0))
  }
}
