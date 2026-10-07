require "rails_helper"

# DYN-09: what the script of the checks does to the page — where it puts its
# message, how it names it for a screen reader, what it does with the
# server's own — run by Node on a field made up for the example: a hint, the
# server's message if any, and the field, in the wrapper Rails puts around a
# wrong one. Each step sets the field and tells the script that the value
# changed or that the field was left; the state of the field is read after it.
RSpec.describe "CheckController" do
  include FieldChecksHelper
  include NodeScript

  def lines
    <<~JS
      class Leaf {
        constructor(tag, marks = "") { Object.assign(this, { tag, className: marks, attributes: new Map(), dataset: {}, children: [], parent: null, textContent: "", value: "", defaultValue: "", validity: { badInput: false } }) }
        get id() { return this.attributes.get("id") ?? "" }
        set id(name) { this.attributes.set("id", name) }
        get classList() { return { replace: (from, to) => { this.className = this.className.split(" ").map((mark) => (mark === from ? to : mark)).join(" ") } } }
        getAttribute(name) { return this.attributes.get(name) ?? null }
        setAttribute(name, value) { this.attributes.set(name, String(value)) }
        removeAttribute(name) { this.attributes.delete(name) }
        append(...leaves) { for (const leaf of leaves) { leaf.parent = this; this.children.push(leaf) } return this }
        before(leaf) { leaf.parent = this.parent; this.parent.children.splice(this.parent.children.indexOf(this), 0, leaf) }
        replaceWith(leaf) { leaf.parent = this.parent; this.parent.children.splice(this.parent.children.indexOf(this), 1, leaf) }
        remove() { this.parent.children.splice(this.parent.children.indexOf(this), 1) }
        closest(selector) { for (let leaf = this; leaf; leaf = leaf.parent) if (leaf.className.split(" ").includes(selector.slice(1))) return leaf; return null }
        all() { return [ this, ...this.children.flatMap((child) => child.all()) ] }
      }
      const page = new Leaf("div", "field")
      const document = { createElement: (tag) => new Leaf(tag), getElementById: (id) => page.all().find((leaf) => leaf.id === id) ?? null }
      const hint = new Leaf("span", "hint")
      const field = new Leaf("input")
      hint.id = "field_hint"
      field.id = "field"
      field.value = field.defaultValue = sent.value
      Object.assign(field.dataset, sent.rules)
      field.setAttribute("aria-describedby", hint.id)
      page.append(hint)
      if (sent.server) {
        const said = new Leaf("span", "field-error")
        said.id = "field_error"
        said.textContent = sent.server
        page.append(said, new Leaf("div", "field_with_errors").append(field))
        field.setAttribute("aria-describedby", "field_hint field_error")
      } else {
        page.append(field)
      }
      const script = new Subject()
      const seen = () => {
        const messages = page.all().filter((leaf) => leaf.className === "field-error")
        return { messages: messages.map((leaf) => leaf.textContent), own: messages[0]?.dataset.checkOwn ?? null, role: messages[0]?.getAttribute("role") ?? null,
                 above: messages[0] ? page.all().indexOf(messages[0]) < page.all().indexOf(field) : null, invalid: field.getAttribute("aria-invalid"),
                 described: field.getAttribute("aria-describedby"), wrapper: field.parent.className }
      }
      console.log(JSON.stringify(sent.steps.map((step) => {
        if ("value" in step) field.value = step.value
        field.validity.badInput = step.unreadable ?? false
        if (step.left) script.leave({ target: field })
        else script.mend({ target: field })
        return seen()
      })))
    JS
  end

  def states(model, attribute, steps, value: "", server: nil)
    rules = field_check(model, attribute).to_h { |name, rule| [ name.to_s.camelize(:lower), rule.to_s ] }
    node(%w[ controllers/field_fault.js controllers/check_controller.js ], lines, { rules:, value:, server:, steps: }).map(&:symbolize_keys)
  end

  let(:untouched) { { messages: [], own: nil, role: nil, above: nil, invalid: nil, described: "field_hint", wrapper: "field" } }
  let(:said) do
    { messages: [ "Call sign is invalid" ], own: "true", role: "status", above: true, invalid: "true",
      described: "field_hint field_error", wrapper: "field" }
  end

  it "says nothing while a value is typed, and says the rule's message above the field when the field is left" do
    expect(states(PatrolCar, :call_sign, [ { value: "p12" }, { left: true }, { left: true } ])).to eq([ untouched, said, said ])
  end

  it "takes its message away, with what it told a screen reader, as soon as the value is mended" do
    expect(states(PatrolCar, :call_sign, [ { value: "p12", left: true }, { value: "P-12" } ])).to eq([ said, untouched ])
  end

  it "keeps the server's message over the value the server judged, and takes it and its frame away for another right one" do
    kept = { messages: [ "Call sign has already been taken" ], own: nil, role: nil, above: true, invalid: nil,
             described: "field_hint field_error", wrapper: "field_with_errors" }

    expect(states(PatrolCar, :call_sign, [ { left: true }, { value: "P-13" } ], value: "P-12", server: kept[:messages].first))
      .to eq([ kept, untouched.merge(wrapper: "field-mended") ])
  end

  it "puts the rule's message in the place of the server's when the field is left with another wrong value" do
    steps = [ { value: "p12" }, { left: true } ]

    expect(states(PatrolCar, :call_sign, steps, value: "P-12", server: "Call sign has already been taken").map { |state| state[:messages] })
      .to eq([ [ "Call sign has already been taken" ], [ "Call sign is invalid" ] ])
  end

  it "takes what a number field cannot read for a wrong value" do
    expect(states(PatrolCar, :crew_size, [ { unreadable: true, left: true } ]).sole)
      .to include(messages: [ "Crew size must be between 1 and 4" ], invalid: "true")
  end

  it "leaves a field that carries no rule alone" do
    expect(states(GuardedSite, :name, [ { value: "x", left: true } ])).to eq([ untouched ])
  end
end
