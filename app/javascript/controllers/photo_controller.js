import { Controller } from "@hotwired/stimulus"

const SIDE = 1600

// CRW-10: the chosen photos are shrunk on the phone one by one to at most
// 1600 px on their longer side, as JPEG, and sent together. A file the
// browser cannot draw goes as it is, and the server says why it refuses it.
// Until the server answers, a refresh of the page waits, and in the closing
// dialog the call is not closed; photos that did not reach the server stay
// chosen, to be sent again.
export default class extends Controller {
  static targets = ["input", "status", "again"]

  async send() {
    const input = this.inputTarget
    if (this.sending || input.files.length === 0) return
    this.busy(true)
    const files = []
    for (const file of input.files) files.push(await this.shrink(file))
    const transfer = new DataTransfer()
    files.forEach((file) => transfer.items.add(file))
    input.files = transfer.files
    input.form.requestSubmit()
  }

  again() {
    if (this.sending || this.inputTarget.files.length === 0) return
    this.busy(true)
    this.inputTarget.form.requestSubmit()
  }

  // The server has answered: the page may go on to show what it said.
  answer({ target }) {
    if (target === this.inputTarget.form) this.waiting = false
  }

  hold(event) {
    if (this.waiting) event.preventDefault()
  }

  reset({ target, detail }) {
    if (target !== this.inputTarget.form) return
    this.busy(false)
    if (detail.fetchResponse) {
      this.inputTarget.value = ""
    } else {
      this.statusTarget.textContent = "Photos not sent; check the connection and send them again."
      this.againTarget.hidden = false
    }
  }

  busy(on) {
    this.sending = on
    this.waiting = on
    this.element.setAttribute("aria-busy", String(on))
    this.statusTarget.textContent = on ? "Sending photos…" : ""
    this.againTarget.hidden = true
    this.element.closest("form")?.querySelectorAll("[type=submit]").forEach((button) => { button.disabled = on })
  }

  async shrink(file) {
    try {
      const bitmap = await createImageBitmap(file, { imageOrientation: "from-image" })
      const scale = Math.min(1, SIDE / Math.max(bitmap.width, bitmap.height))
      const canvas = document.createElement("canvas")
      canvas.width = Math.round(bitmap.width * scale)
      canvas.height = Math.round(bitmap.height * scale)
      canvas.getContext("2d").drawImage(bitmap, 0, 0, canvas.width, canvas.height)
      bitmap.close()
      const blob = await new Promise((resolve) => canvas.toBlob(resolve, "image/jpeg", 0.85))
      return blob ? new File([blob], `${file.name.replace(/\.[^.]*$/, "")}.jpg`, { type: "image/jpeg" }) : file
    } catch {
      return file
    }
  }
}
