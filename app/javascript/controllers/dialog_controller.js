import { Controller } from "@hotwired/stimulus"

// DYN-07: a dialog loaded into the modal frame opens as a modal; closing it
// empties the frame, so the same link opens it fresh next time. Its own form,
// once answered, closes it; a refresh of the page in place after someone
// else changes a call leaves the open dialog and what was typed in it alone.
export default class extends Controller {
  connect() {
    this.element.showModal()
    this.element.addEventListener("close", this.forget)
    this.element.addEventListener("turbo:submit-end", this.finish)
    document.addEventListener("turbo:before-morph-element", this.keep)
  }

  disconnect() {
    this.element.removeEventListener("close", this.forget)
    this.element.removeEventListener("turbo:submit-end", this.finish)
    document.removeEventListener("turbo:before-morph-element", this.keep)
  }

  close() {
    this.element.close()
  }

  finish = (event) => {
    if (event.detail.success) this.element.close()
  }

  keep = (event) => {
    if (event.target.matches("turbo-frame#modal") && event.target.contains(this.element)) event.preventDefault()
  }

  forget = () => {
    this.element.closest("turbo-frame")?.removeAttribute("src")
    this.element.remove()
  }
}
