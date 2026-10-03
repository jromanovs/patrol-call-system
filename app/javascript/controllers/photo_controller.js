import { Controller } from "@hotwired/stimulus"

const SIDE = 1600

// CRW-10: the chosen photos are shrunk on the phone to at most 1600 px on
// their longer side, as JPEG, and sent at once. A file the browser cannot
// draw goes as it is, and the server says why it refuses it.
export default class extends Controller {
  static targets = ["input"]

  async send() {
    const input = this.inputTarget
    if (this.sending || input.files.length === 0) return
    this.sending = true
    this.element.setAttribute("aria-busy", "true")
    const files = await Promise.all([...input.files].map((file) => this.shrink(file)))
    const transfer = new DataTransfer()
    files.forEach((file) => transfer.items.add(file))
    input.files = transfer.files
    input.form.requestSubmit()
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
