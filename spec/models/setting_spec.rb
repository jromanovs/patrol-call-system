require "rails_helper"

RSpec.describe Setting do
  subject(:setting) { described_class.current }

  it "keeps car positions for 24 months unless the administrator says otherwise (TRK-05, BR-20)" do
    expect(setting.position_months).to eq(24)
  end

  it "is one for the whole system, by the database as well", :aggregate_failures do
    expect([ described_class.current, described_class.current ].uniq.size).to eq(1)
    expect { described_class.transaction(requires_new: true) { described_class.create! } }
      .to raise_error(ActiveRecord::RecordNotUnique, /settings_one_row/)
  end

  it "takes the row another request made first, when it loses the race, also inside a transaction" do
    existing = described_class.current
    allow(described_class).to receive(:first).and_return(nil)

    expect(described_class.transaction { described_class.current }).to eq(existing)
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

  it "is held to 3 months and to 1200 by the database as well", :aggregate_failures do
    # The row made first: a refusal ends its own transaction, and a row made
    # inside it would go with it.
    row = described_class.current
    [ 2, 1201 ].each do |months|
      expect { described_class.transaction(requires_new: true) { row.update_columns(position_months: months) } }
        .to raise_error(ActiveRecord::StatementInvalid, /settings_position_months/)
    end
  end

  it "gives the period as a length of time" do
    setting.position_months = 6

    expect(setting.kept).to eq(6.months)
  end

  describe "the period calls are kept (BR-23)" do
    it "is 24 months unless the administrator says otherwise" do
      expect(setting.call_months).to eq(24)
    end

    it "takes whole months, 3 to 1200", :aggregate_failures do
      [ 2, 2.5, nil, "many" ].each do |months|
        setting.call_months = months
        expect(setting).not_to be_valid
        expect(setting.errors.full_messages).to eq([ "Keep calls for at least 3 months" ])
      end
      setting.call_months = 1201
      expect(setting.tap(&:validate).errors.full_messages).to eq([ "Keep calls for at most 1200 months" ])
    end

    it "is held to its bounds by the database as well", :aggregate_failures do
      row = described_class.current
      [ 2, 1201 ].each do |months|
        expect { described_class.transaction(requires_new: true) { row.update_columns(call_months: months) } }
          .to raise_error(ActiveRecord::StatementInvalid, /settings_call_months/)
      end
    end

    it "gives the first day whose calls are still kept, by calendar months", :aggregate_failures do
      travel_to(Time.zone.local(2026, 10, 4, 12, 0))
      expect(setting.calls_kept_from).to eq(Date.new(2024, 10, 4))

      setting.call_months = 3
      travel_to(Time.zone.local(2027, 5, 31, 12, 0))
      expect(setting.calls_kept_from).to eq(Date.new(2027, 2, 28))
    end
  end
end
