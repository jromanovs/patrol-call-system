import { Controller } from "@hotwired/stimulus"
import { verdict } from "controllers/field_fault"

// DYN-09: a field left with a wrong value says so at once, above itself, in
// the words the server would use, and stops saying it when the value is
// mended. The server checks everything again when the form is sent.
export default class extends Controller {
  leave(event) {
    this.judge(event.target, true)
  }

  mend(event) {
    this.judge(event.target, false)
  }

  judge(field, left) {
    const words = field.dataset?.checkMessage
    if (!words) return
    const message = this.message(field)
    const state = { value: field.value, unreadable: field.validity.badInput, judged: field.defaultValue, shown: this.shown(message), left }
    const ruling = verdict(state, field.dataset)
    if (ruling === "say" && message?.textContent !== words) this.say(field, words, message)
    if (ruling === "unsay") this.unsay(field, message)
  }

  message(field) {
    return field.id ? document.getElementById(`${field.id}_error`) : null
  }

  // Whose message stands above the field: the page marks its own.
  shown(message) {
    if (!message) return ""
    return message.dataset.checkOwn ? "page" : "server"
  }

  // The message waits for its turn to be read out (role "status"): the
  // reader has gone on to the next field, whose name comes first.
  say(field, words, former) {
    const message = document.createElement("span")
    message.className = "field-error"
    message.id = `${field.id}_error`
    message.dataset.checkOwn = "true"
    message.setAttribute("role", "status")
    message.textContent = words
    if (former) former.replaceWith(message)
    else field.before(message)
    field.setAttribute("aria-invalid", "true")
    field.setAttribute("aria-describedby", [...new Set([...this.described(field), message.id])].join(" "))
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
