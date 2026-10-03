import { Controller } from "@hotwired/stimulus"

// DYN-07: a dialog loaded into the modal frame opens as a modal; closing it
// empties the frame, so the same link opens it fresh next time. Its own form,
// once answered, closes it; a refresh of the page in place after someone
// else changes a call leaves the open dialog and what was typed in it alone.
export default class extends Controller {
  // DYN-20: the seconds after which a dialog left alone closes by itself.
  static values = { timeout: Number }
  // What a dialog says when its form got no answer, if it has such words.
  static targets = [ "failed" ]

  connect() {
    this.element.showModal()
    if (this.hasTimeoutValue) this.timer = setTimeout(() => this.close(), this.timeoutValue * 1000)
    this.element.addEventListener("submit", this.stay)
    this.element.addEventListener("close", this.forget)
    this.element.addEventListener("turbo:submit-end", this.finish)
    document.addEventListener("turbo:before-morph-element", this.keep)
  }

  disconnect() {
    clearTimeout(this.timer)
    this.element.removeEventListener("submit", this.stay)
    this.element.removeEventListener("close", this.forget)
    this.element.removeEventListener("turbo:submit-end", this.finish)
    document.removeEventListener("turbo:before-morph-element", this.keep)
  }

  close() {
    this.element.close()
  }

  // An answer given, the dialog waits for it to go through.
  stay = () => {
    clearTimeout(this.timer)
  }

  // A form that changes only a part of the dialog, such as its photos, leaves
  // it open.
  finish = (event) => {
    const part = event.target.dataset.turboFrame
    if (part && this.element.querySelector(`turbo-frame#${CSS.escape(part)}`)) return
    if (event.detail.success) this.element.close()
    else if (this.hasFailedTarget) this.failedTarget.hidden = false
  }

  keep = (event) => {
    if (event.target.matches("turbo-frame#modal") && event.target.contains(this.element)) event.preventDefault()
  }

  forget = () => {
    this.element.closest("turbo-frame")?.removeAttribute("src")
    this.element.remove()
  }
}
