require "rails_helper"

RSpec.describe "Factories" do
  # UPD-09: Help given is for a crew's SOS only, and an SOS has outcomes of
  # its own; the traits made from the outcomes cannot all fit every call.
  let(:of_another_kind) do
    %w[ alarm_call+help_given client_call+help_given sos_call+intrusion_confirmed sos_call+fire_confirmed
        sos_call+technical_fault ]
  end

  it "builds every factory and trait into a valid record, but an outcome of another kind of call" do
    expect { FactoryBot.lint(traits: true) }.to raise_error(FactoryBot::InvalidFactoryError) { |error|
      expect(error.message.scan(/^\* (\S+) - /).flatten).to match_array(of_another_kind)
    }
  end
end
