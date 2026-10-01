import { Controller } from "@hotwired/stimulus"

// DYN-04: the form shows only the fields of the chosen call type; the other
// type's fields are disabled, so they are not sent. Choosing a type or an
// alarm type sets the priority to its BR-2 default.
export default class extends Controller {
  static targets = ["alarm", "client", "priority", "alarmType"]
  static values = { priorities: Object }

  toggle() {
    const kind = this.element.querySelector("input[name='call[kind]']:checked")?.value ?? "alarm"
    this.show(this.alarmTarget, kind === "alarm")
    this.show(this.clientTarget, kind === "client")
    this.priorityTarget.value = kind === "alarm" ? this.alarmDefault() : "normal"
  }

  alarmTypeChanged() {
    this.priorityTarget.value = this.alarmDefault()
  }

  alarmDefault() {
    return this.prioritiesValue[this.alarmTypeTarget.value] ?? ""
  }

  show(fieldset, visible) {
    fieldset.hidden = !visible
    fieldset.disabled = !visible
  }
}
