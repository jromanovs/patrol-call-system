import { Controller } from "@hotwired/stimulus"
import { fault } from "controllers/field_fault"

// DYN-09: a field left with a wrong value says so at once, above itself, in
// the words the server would use, and stops saying it when the value is
// mended. The server checks everything again when the form is sent.
export default class extends Controller {
  leave(event) {
    this.judge(event.target)
  }

  // While a field is being filled for the first time it is left alone.
  mend(event) {
    if (this.message(event.target)) this.judge(event.target)
  }

  judge(field) {
    const words = field.dataset?.checkMessage
    if (!words) return
    const wrong = fault(field.value, field.dataset)
    const message = this.message(field)
    if (wrong && !message) this.say(field, words)
    // A message in other words is the server's own and stays.
    if (!wrong && message?.textContent === words) this.unsay(field, message)
  }

  message(field) {
    return field.id ? document.getElementById(`${field.id}_error`) : null
  }

  say(field, words) {
    const message = document.createElement("span")
    message.className = "field-error"
    message.id = `${field.id}_error`
    message.setAttribute("role", "alert")
    message.textContent = words
    field.before(message)
    field.setAttribute("aria-invalid", "true")
    field.setAttribute("aria-describedby", [...this.described(field), message.id].join(" "))
  }

  unsay(field, message) {
    field.setAttribute("aria-describedby", this.described(field).filter((id) => id !== message.id).join(" "))
    field.removeAttribute("aria-invalid")
    // The server frames a wrong field by a wrapper of its own.
    field.closest(".field_with_errors")?.classList.replace("field_with_errors", "field-mended")
    message.remove()
  }

  described(field) {
    return (field.getAttribute("aria-describedby") ?? "").split(" ").filter(Boolean)
  }
}
