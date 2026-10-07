// DYN-09: whether a value breaks the rule its field carries from the server.
// The rule is the model's own (FieldChecksHelper); a blank is left to the
// server, which alone knows whether the field may stay empty.
export function fault(value, rules) {
  if (value === "") return false
  if (rules.checkPattern) return !new RegExp(rules.checkPattern).test(prepared(value, rules))
  if (rules.checkLeast !== undefined) return !whole(value) || Number(value) < Number(rules.checkLeast) || Number(value) > Number(rules.checkMost)
  return false
}

// What becomes of the message above a field: "say" the rule's own, "unsay"
// the one that stands there, or "keep" things as they are. A field is told
// by its value, whether the browser could read what was typed (a number
// field gives no value for "9e"), the value the server judged last, whose
// message is shown — "page", "server" or none — and whether it is left.
// While a field is typed in nothing is said anew. The server's message
// holds for the value the server judged and for no other.
export function verdict(field, rules) {
  if (field.unreadable || fault(field.value, rules)) return field.left ? "say" : "keep"
  if (!field.shown) return "keep"
  return field.shown === "server" && field.value === field.judged ? "keep" : "unsay"
}

// As the server prepares a value before it judges it. It trims what Ruby
// calls white space, which is less than a browser's trim takes.
function prepared(value, rules) {
  const trimmed = rules.checkTrim ? value.replace(/^[\t\n\v\f\r \0]+|[\t\n\v\f\r \0]+$/g, "") : value
  return rules.checkUpper ? trimmed.toUpperCase() : trimmed
}

function whole(value) {
  return /^[+-]?\d+$/.test(value)
}
