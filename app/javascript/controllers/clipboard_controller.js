import { Controller } from "@hotwired/stimulus"

// TRK-02: Copy puts the identifier on the clipboard and says so; where the
// browser refuses, the identifier is selected and the page says that it is
// to be copied by hand, so that nothing else is pasted in its place. What it
// says comes from the page, in the language of the page.
export default class extends Controller {
  static targets = ["source", "button", "status"]
  static values = { copiedText: String, failedText: String }

  async copy() {
    try {
      await navigator.clipboard.writeText(this.sourceTarget.textContent.trim())
      this.buttonTarget.textContent = this.copiedTextValue
      this.statusTarget.textContent = this.copiedTextValue
    } catch {
      window.getSelection().selectAllChildren(this.sourceTarget)
      this.statusTarget.textContent = this.failedTextValue
    }
  }
}
