require "rails_helper"
require "open3"

# DYN-09: the judgement the browser makes of a value when its field is left,
# run by Node from the page's own module with the rule the page carries, and
# set beside the server's judgement of the same value. A blank is left to the
# server and is not among the values.
RSpec.describe "FieldFault" do
  include FieldChecksHelper

  # The rule as the field's data attributes give it to a script: every value a text.
  def carried(model, attribute)
    field_check(model, attribute).except(:check_message).to_h { |name, value| [ name.to_s.camelize(:lower), value.to_s ] }
  end

  def browser(model, attribute, values)
    script = <<~JS
      import { fault } from #{Rails.root.join('app/javascript/controllers/field_fault.js').to_s.to_json}
      let sent = ""
      for await (const part of process.stdin) sent += part
      const { rules, values } = JSON.parse(sent)
      console.log(JSON.stringify(values.map((value) => fault(value, rules))))
    JS
    printed, said, result = Open3.capture3("node", "--input-type=module", "-e", script,
                                           stdin_data: { rules: carried(model, attribute), values: }.to_json)
    raise said unless result.success?

    JSON.parse(printed)
  end

  # Whether the server, checking the whole record, gives the field's message
  # for the value. Its other messages, of a taken or a missing value, are
  # not the browser's to give.
  def server(model, attribute, values)
    words = field_check(model, attribute).fetch(:check_message)
    values.map { |value| model.new(attribute => value).tap(&:valid?).errors.full_messages_for(attribute).include?(words) }
  end

  {
    [ GuardedSite, :contract_number ] => [ "C-12345", "C-00001", "c-12345", "C-1234", "C-123456", "C12345", "C-12345 ", " C-12345",
                                           "C-1234٥", "С-12345", "C-12345\n", "123" ],
    [ GuardedSite, :keyholder_phone ] => [ "+37100000001", "+1234567", "+123456789012345", "+1234567890123456", "37100000001",
                                           "+371 0000 0001", "++37100000001", "12345" ],
    [ ClientCall, :caller_phone ] => [ "+37100000001", "12345", "+371-00000001" ],
    [ PatrolCar, :call_sign ] => [ "P-12", "ABC-123", "ABCD-1", "P-1234", "p-12", "P12", "P-12 ", "Р-12", "p12" ],
    [ PatrolCar, :plate_number ] => [ "ZZ-0012", "zz-0012", " ab-1 ", "A", "ABCDEFGHIJK", "AB 12", "ĀB-12", "ab 1", " ", "ß1" ],
    [ PatrolCar, :crew_size ] => [ "1", "4", "0", "5", "9", "2.5", "x", "-1", "+2", " 3", "04", "1e0" ],
    [ AlarmCall, :sensor_zone ] => [ "1", "99", "0", "100", "12.0", "zone" ]
  }.each do |(model, attribute), values|
    it "judges #{model.model_name.human.downcase} #{attribute} as the server does", :aggregate_failures do
      refused = server(model, attribute, values)

      expect(browser(model, attribute, values)).to eq(refused)
      expect(refused.uniq).to contain_exactly(true, false)
    end
  end

  it "leaves a blank to the server, whatever the rule" do
    expect(browser(GuardedSite, :contract_number, [ "" ]) + browser(PatrolCar, :crew_size, [ "" ])).to eq([ false, false ])
  end

  it "finds no fault in a field that carries no rule" do
    expect(browser(GuardedSite, :name, [ "x", "Harbour warehouse" ])).to eq([ false, false ])
  end
end
