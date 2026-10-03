import { Controller } from "@hotwired/stimulus"

// TRK-02: Copy puts the identifier on the clipboard and says so; where the
// browser refuses, the identifier is selected, to be copied by hand.
export default class extends Controller {
  static targets = ["source", "button"]

  async copy() {
    try {
      await navigator.clipboard.writeText(this.sourceTarget.textContent.trim())
      this.buttonTarget.textContent = "Copied"
    } catch {
      window.getSelection().selectAllChildren(this.sourceTarget)
    }
  }
}
