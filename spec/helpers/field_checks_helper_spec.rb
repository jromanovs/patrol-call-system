require "rails_helper"

RSpec.describe FieldChecksHelper do
  describe "#field_check (DYN-09)" do
    it "gives a field with a format the pattern as a browser reads it, and the server's own message", :aggregate_failures do
      expect(helper.field_check(GuardedSite, :contract_number))
        .to eq(check_pattern: "^C-\\d{5}$", check_message: "Contract number is invalid")
      expect(helper.field_check(GuardedSite, :keyholder_phone))
        .to eq(check_pattern: "^\\+\\d{8,15}$", check_message: "Keyholder phone is invalid")
      expect(helper.field_check(ClientCall, :caller_phone))
        .to eq(check_pattern: "^\\+\\d{8,15}$", check_message: "Caller phone is invalid")
      expect(helper.field_check(PatrolCar, :call_sign))
        .to eq(check_pattern: "^[A-Z]{1,3}-\\d{1,3}$", check_message: "Call sign is invalid")
    end

    # The server trims a plate number and writes it in capitals before it
    # judges it: the browser is told to do the same.
    it "tells the browser what the server does to a value before judging it" do
      expect(helper.field_check(PatrolCar, :plate_number))
        .to eq(check_pattern: "^[A-Z0-9-]{2,10}$", check_message: "Plate number is invalid", check_trim: true, check_upper: true)
    end

    it "gives a field with limits its least and its most, and the server's own message", :aggregate_failures do
      expect(helper.field_check(PatrolCar, :crew_size))
        .to eq(check_least: 1, check_most: 4, check_message: "Crew size must be between 1 and 4")
      expect(helper.field_check(AlarmCall, :sensor_zone))
        .to eq(check_least: 1, check_most: 99, check_message: "Sensor zone must be from 1 to 99")
    end

    it "gives nothing for a field the server checks otherwise or not at all", :aggregate_failures do
      expect(helper.field_check(GuardedSite, :name)).to eq({})
      expect(helper.field_check(PatrolCar, :model)).to eq({})
      expect(helper.field_check(PatrolCar, :district)).to eq({})
    end

    it "words the message in the language of the page" do
      message = I18n.with_locale(:lv) { helper.field_check(PatrolCar, :crew_size)[:check_message] }

      expect(message).to eq(I18n.with_locale(:lv) { PatrolCar.new(crew_size: 9).tap(&:valid?).errors.full_messages_for(:crew_size).sole })
    end
  end
end
