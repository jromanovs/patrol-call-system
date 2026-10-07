require "rails_helper"

# DYN-09: the judgement the browser makes of a value when its field is left,
# run by Node from the page's own module with the rule the page carries, and
# set beside the server's judgement of the same value. A blank is left to the
# server and is not among the values.
RSpec.describe "FieldFault" do
  include FieldChecksHelper
  include NodeScript

  # The values each field is tried with.
  def self.samples
    {
      [ GuardedSite, :contract_number ] => [ "C-12345", "C-00001", "c-12345", "C-1234", "C-123456", "C12345", "C-12345 ", " C-12345",
                                             "C-1234٥", "С-12345", "C-12345\n", "123" ],
      [ GuardedSite, :keyholder_phone ] => [ "+37100000001", "+1234567", "+123456789012345", "+1234567890123456", "37100000001",
                                             "+371 0000 0001", "++37100000001", "12345" ],
      [ ClientCall, :caller_phone ] => [ "+37100000001", "12345", "+371-00000001" ],
      [ PatrolCar, :call_sign ] => [ "P-12", "ABC-123", "ABCD-1", "P-1234", "p-12", "P12", "P-12 ", "Р-12", "p12" ],
      [ PatrolCar, :plate_number ] => [ "ZZ-0012", "zz-0012", " ab-1 ", "A", "ABCDEFGHIJK", "AB 12", "ĀB-12", "ab 1", " ", "ß1",
                                        "\u00A0AB-1", "\tzz-1\n" ],
      [ PatrolCar, :crew_size ] => [ "1", "4", "0", "5", "9", "2.5", "x", "-1", "+2", " 3", "04", "1e0" ],
      [ AlarmCall, :sensor_zone ] => [ "1", "99", "0", "100", "12.0", "zone" ]
    }
  end

  let(:samples) { self.class.samples }

  # The rule as the field's data attributes give it to a script: every value a text.
  def carried(model, attribute)
    field_check(model, attribute).except(:check_message).to_h { |name, value| [ name.to_s.camelize(:lower), value.to_s ] }
  end

  def browser(model, attribute, values)
    node("controllers/field_fault.js", "console.log(JSON.stringify(sent.values.map((value) => fault(value, sent.rules))))",
         rules: carried(model, attribute), values:)
  end

  # Whether the server, checking the whole record, gives the field's message
  # for the value. Its other messages, of a taken or a missing value, are
  # not the browser's to give.
  def server(model, attribute, values)
    words = field_check(model, attribute).fetch(:check_message)
    values.map { |value| model.new(attribute => value).tap(&:valid?).errors.full_messages_for(attribute).include?(words) }
  end

  samples.each do |(model, attribute), given|
    it "judges #{model.model_name.human.downcase} #{attribute} as the server does", :aggregate_failures do
      refused = server(model, attribute, given)

      expect(browser(model, attribute, given)).to eq(refused)
      expect(refused.uniq).to contain_exactly(true, false)
    end
  end

  # A field given a rule in a form without values here would be judged by the
  # browser with nothing to say that the server judges it the same way.
  it "holds values for every field that carries a rule in a form", :aggregate_failures do
    views = Rails.root.glob("app/views/**/*.haml").map(&:read)
    drawn = views.flat_map { |view| view.scan(/field_check\((\w+), :(\w+)\)/) }

    expect(drawn.map { |model, attribute| [ model.constantize, attribute.to_sym ] }).to match_array(samples.keys)
    expect(views.sum { |view| view.scan("field_check(").size }).to eq(drawn.size)
  end

  it "leaves a blank to the server, whatever the rule" do
    expect(browser(GuardedSite, :contract_number, [ "" ]) + browser(PatrolCar, :crew_size, [ "" ])).to eq([ false, false ])
  end

  it "finds no fault in a field that carries no rule" do
    expect(browser(GuardedSite, :name, [ "x", "Harbour warehouse" ])).to eq([ false, false ])
  end

  # What the page does with the message above a field: says the rule's own,
  # takes the message away, or keeps what is there. A field is told by its
  # value, whether the browser could read what was typed, the value the
  # server judged last, whose message stands above it, and whether it is left.
  describe "the message of a field" do
    def field(**given) = { value: "", unreadable: false, judged: "", shown: "", left: true }.merge(given)

    def verdicts(model, attribute, fields)
      node("controllers/field_fault.js", "console.log(JSON.stringify(sent.fields.map((field) => verdict(field, sent.rules))))",
           rules: carried(model, attribute), fields:)
    end

    it "is not said while a field is typed in, and is said when the field is left wrong" do
      typed = field(value: "p12", left: false)

      expect(verdicts(PatrolCar, :call_sign, [ typed, typed.merge(left: true), field(value: "P-12") ])).to eq(%w[ keep say keep ])
    end

    it "goes, when the page said it, once the value is right or the field is emptied" do
      said = [ field(value: "P-12", shown: "page"), field(value: "P-12", shown: "page", left: false), field(shown: "page") ]

      expect(verdicts(PatrolCar, :call_sign, said)).to eq(%w[ unsay unsay unsay ])
    end

    # A form sent with an empty field: entering the field and leaving it
    # changes nothing, and the server's message stays.
    it "stays, when the server said it, over the very value the server judged, an empty one too" do
      judged = [ field(shown: "server"), field(shown: "server", left: false),
                 field(value: "P-12", judged: "P-12", shown: "server") ]

      expect(verdicts(PatrolCar, :call_sign, judged)).to eq(%w[ keep keep keep ])
    end

    it "goes, when the server said it, once the value is another one that breaks no rule" do
      changed = [ field(value: "P-13", judged: "P-12", shown: "server", left: false), field(judged: "p12", shown: "server") ]

      expect(verdicts(PatrolCar, :call_sign, changed)).to eq(%w[ unsay unsay ])
    end

    it "gives way to the rule's own when the field is left with another wrong value, not while it is typed in" do
      wrong = field(value: "p12", judged: "P-12", shown: "server")

      expect(verdicts(PatrolCar, :call_sign, [ wrong, wrong.merge(left: false) ])).to eq(%w[ say keep ])
    end

    # A number field gives a script nothing when it cannot read what was typed.
    it "is said for what a number field cannot read, and stays while that is typed" do
      unread = field(unreadable: true)

      expect(verdicts(PatrolCar, :crew_size, [ unread, unread.merge(shown: "page", left: false) ])).to eq(%w[ say keep ])
    end
  end
end
