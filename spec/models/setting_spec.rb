require "rails_helper"

RSpec.describe Setting do
  subject(:setting) { described_class.current }

  it "keeps car positions for 24 months unless the administrator says otherwise (TRK-05, BR-20)" do
    expect(setting.position_months).to eq(24)
  end

  it "is one for the whole system" do
    expect([ described_class.current, described_class.current ].uniq.size).to eq(1)
  end

  it "takes a period of whole months, not below 3", :aggregate_failures do
    [ 3, 24, 120 ].each { |months| expect(setting.tap { |one| one.position_months = months }).to be_valid }

    [ 2, 0, -6, 2.5, nil, "many" ].each do |months|
      setting.position_months = months
      expect(setting).not_to be_valid
      expect(setting.errors.full_messages).to eq([ "Keep positions for at least 3 months" ])
    end
  end

  it "takes no period beyond what a date can count", :aggregate_failures do
    setting.position_months = 1201

    expect(setting).not_to be_valid
    expect(setting.errors.full_messages).to eq([ "Keep positions for at most 1200 months" ])
  end

  it "is held to 3 months by the database as well" do
    expect { described_class.transaction(requires_new: true) { setting.update_columns(position_months: 2) } }
      .to raise_error(ActiveRecord::StatementInvalid, /settings_position_months/)
  end

  it "gives the period as a length of time" do
    setting.position_months = 6

    expect(setting.kept).to eq(6.months)
  end
end
