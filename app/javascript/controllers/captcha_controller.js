import { Controller } from "@hotwired/stimulus"

// USR-10: the check of the sign-in page shows the words of its library. The
// library keeps the words of each language in a list of its own and shows
// those of the language the page names; the page hands it the words of that
// language here.
export default class extends Controller {
  static values = { words: Object }

  connect() {
    globalThis.$altcha.i18n.set(document.documentElement.lang, this.wordsValue)
  }
}
