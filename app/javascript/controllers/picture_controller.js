import { Controller } from "@hotwired/stimulus"

const SIDE = 256

// USR-07: the chosen photo is cut to a square around its middle and reduced
// to 256 px, as JPEG on white, then shown in place of the present picture
// and sent so; Save waits until that is done, or the photo would go as it
// was taken. A file the browser cannot draw goes as it is, and the server
// says why it refuses it.
export default class extends Controller {
  static targets = ["input", "current", "preview", "save"]

  async chosen() {
    const input = this.inputTarget
    if (input.files.length === 0) return
    this.saveTarget.disabled = true
    try {
      const file = await this.square(input.files[0])
      const transfer = new DataTransfer()
      transfer.items.add(file)
      input.files = transfer.files
      this.show(file)
    } finally {
      this.saveTarget.disabled = false
    }
  }

  disconnect() {
    URL.revokeObjectURL(this.previewTarget.src)
  }

  show(file) {
    URL.revokeObjectURL(this.previewTarget.src)
    this.previewTarget.src = URL.createObjectURL(file)
    this.previewTarget.hidden = false
    this.currentTarget.hidden = true
  }

  async square(file) {
    try {
      const bitmap = await createImageBitmap(file, { imageOrientation: "from-image" })
      const side = Math.min(bitmap.width, bitmap.height)
      const canvas = document.createElement("canvas")
      canvas.width = canvas.height = SIDE
      const context = canvas.getContext("2d")
      context.fillStyle = "#ffffff"
      context.fillRect(0, 0, SIDE, SIDE)
      context.drawImage(bitmap, (bitmap.width - side) / 2, (bitmap.height - side) / 2, side, side, 0, 0, SIDE, SIDE)
      bitmap.close()
      const blob = await new Promise((resolve) => canvas.toBlob(resolve, "image/jpeg", 0.9))
      return blob ? new File([blob], "picture.jpg", { type: "image/jpeg" }) : file
    } catch {
      return file
    }
  }
}
