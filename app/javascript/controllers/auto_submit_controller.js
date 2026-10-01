import { Controller } from "@hotwired/stimulus"

// DYN-05: the list follows the search and the filters without a button. A
// short pause after a key keeps it from reloading on every key; the order
// chosen in the list (now in the page address) goes along.
export default class extends Controller {
  submit() {
    clearTimeout(this.timer)
    this.timer = setTimeout(() => {
      const current = new URL(window.location.href).searchParams
      for (const name of ["sort", "direction"]) {
        const field = this.element.elements.namedItem(name)
        if (field) field.value = current.get(name) ?? ""
      }
      // Empty fields stay out of the page address; the form reads its fields
      // while it submits, so they are switched on again right after.
      const blanks = [...this.element.elements].filter((field) => field.name && field.value === "" && !field.disabled)
      blanks.forEach((field) => { field.disabled = true })
      this.element.requestSubmit()
      blanks.forEach((field) => { field.disabled = false })
    }, 300)
  }

  disconnect() {
    clearTimeout(this.timer)
  }
}
