// DYN-09: whether a value breaks the rule its field carries from the server.
// The rule is the model's own (FieldChecksHelper); a blank is left to the
// server, which alone knows whether the field may stay empty.
export function fault(value, rules) {
  if (value === "") return false
  if (rules.checkPattern) return !new RegExp(rules.checkPattern).test(prepared(value, rules))
  if (rules.checkLeast !== undefined) return !whole(value) || Number(value) < Number(rules.checkLeast) || Number(value) > Number(rules.checkMost)
  return false
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
