import { Controller } from "@hotwired/stimulus"

// DYN-07: a dialog loaded into the modal frame opens as a modal; closing it
// empties the frame, so the same link opens it fresh next time.
export default class extends Controller {
  connect() {
    this.element.showModal()
    this.element.addEventListener("close", this.forget)
  }

  disconnect() {
    this.element.removeEventListener("close", this.forget)
  }

  close() {
    this.element.close()
  }

  forget = () => {
    this.element.closest("turbo-frame")?.removeAttribute("src")
    this.element.remove()
  }
}
