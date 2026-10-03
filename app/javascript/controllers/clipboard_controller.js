import { Controller } from "@hotwired/stimulus"

// TRK-02: Copy puts the identifier on the clipboard and says so; where the
// browser refuses, the identifier is selected and the page says that it is
// to be copied by hand, so that nothing else is pasted in its place.
export default class extends Controller {
  static targets = ["source", "button", "status"]

  async copy() {
    try {
      await navigator.clipboard.writeText(this.sourceTarget.textContent.trim())
      this.buttonTarget.textContent = "Copied"
      this.statusTarget.textContent = "Copied"
    } catch {
      window.getSelection().selectAllChildren(this.sourceTarget)
      this.statusTarget.textContent = "Not copied: the identifier is selected, copy it by hand."
    }
  }
}
