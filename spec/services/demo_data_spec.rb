require "rails_helper"

RSpec.describe DemoData do
  include_context "without the seeded records"

  let(:emails) { %w[ administrator@example.com dispatcher@example.com supervisor@example.com ] }
  let(:result) { described_class.new.call }
  let(:demo_calls) { Call.where(registered_by: User.find_by!(email_address: "dispatcher@example.com")) }

  before { Rails.application.load_seed }

  it "adds 8 sites at register addresses of public buildings, with fictitious clients (STO-05)", :aggregate_failures do
    expect { result }.to change(GuardedSite, :count).from(4).to(12)

    added = GuardedSite.where.not(contract_number: %w[ C-00011 C-00012 C-00013 C-00014 ]).includes(:address)
    expect(added.pluck(:contract_number)).to match_array((15..22).map { |n| format("C-%05d", n) })
    expect(added.map { |site| site.address.full_address.split(",").first })
      .to contain_exactly("Jaņa Rozentāla laukums 1", "Rātslaukums 1", "Kronvalda bulvāris 2", "Dzirciema iela 16",
                          "Meža prospekts 1", "Skanstes iela 21", "Brīvības iela 75", "Nēģu iela 7")
    expect(added.map(&:client_name)).to all(match(/\A(Example|Sample|Test) [A-Z][a-z]+ Ltd\z/))
    expect(added.map(&:keyholder_phone)).to all(match(/\A\+37100000\d{3}\z/))
  end

  it "adds three users, one per role, and gives the password of each (STO-05)", :aggregate_failures do
    expect(result.passwords.keys).to match_array(emails)
    expect(User.order(:email_address).pluck(:email_address, :role))
      .to eq([ %w[ administrator@example.com administrator ], %w[ dispatcher@example.com dispatcher ],
               %w[ supervisor@example.com supervisor ] ])
    result.passwords.each do |email, password|
      expect(User.authenticate_by(email_address: email, password:)).to be_present, email
    end
  end

  it "adds 150 finished calls of the last 60 days whose steps follow each other (STO-05)", :aggregate_failures do
    travel_to(Time.zone.local(2026, 10, 2, 12, 0)) { result }

    expect(demo_calls.count).to eq(150)
    expect(demo_calls.distinct.pluck(:status)).to match_array(%w[ closed cancelled ])
    expect(demo_calls.minimum(:received_at)).to be >= Time.zone.local(2026, 8, 3, 12, 0)
    expect(demo_calls.maximum(:closed_at)).to be <= Time.zone.local(2026, 10, 2, 12, 0)
    demo_calls.each do |call|
      steps = [ call.received_at, call.dispatched_at, call.accepted_at, call.arrived_at, call.closed_at ].compact
      expect(steps).to eq(steps.sort), "call #{call.id}"
      expect(call.outcome.present?).to eq(call.closed?), "call #{call.id}"
    end
    expect(demo_calls.closed.where(arrived_at: nil)).to be_empty
    expect(demo_calls.closed.where(accepted_at: nil)).to be_empty
    expect(PatrolCar.where(id: demo_calls.select(:patrol_car_id)).pluck(:status)).not_to include("out_of_service")
  end

  it "adds no active call and refreshes no open board (STO-05)", :aggregate_failures do
    allow(Turbo::StreamsChannel).to receive(:broadcast_refresh_later_to)

    result

    expect(Call.where(status: Call::ACTIVE)).to be_empty
    expect(Turbo::StreamsChannel).not_to have_received(:broadcast_refresh_later_to)
  end

  it "gives the statistics something to show (CALC-02, CALC-03)", :aggregate_failures do
    result
    statistics = CallStatistics.new(Call.all)

    expect(statistics.false_alarms.share).to be_between(30, 70)
    expect(statistics.response).to be_between(5, 30)
    expect(statistics.false_alarm_sites.size).to eq(5)
  end

  it "puts the calls on the demo sites and cars only, never on the owner's own (STO-05)", :aggregate_failures do
    site = create(:guarded_site)
    car = create(:patrol_car)

    result

    expect(Call.where(guarded_site: site)).to be_empty
    expect(Call.where(patrol_car: car)).to be_empty
  end

  it "keeps every car on one call at a time, the calls already there included (STO-05)" do
    car = PatrolCar.find_by!(call_sign: "P-12")
    create(:alarm_call, received_at: 10.days.ago)
      .update_columns(status: Call.statuses[:dispatched], patrol_car_id: car.id, dispatched_at: 10.days.ago)

    result

    Call.where.not(patrol_car_id: nil).group_by(&:patrol_car_id).each_value do |calls|
      spans = calls.map { |call| call.dispatched_at..(call.closed_at || Time.current) }.sort_by(&:begin)
      expect(spans.each_cons(2).none? { |first, second| second.begin < first.end }).to be(true)
    end
  end

  it "loads nothing when a demo e-mail address belongs to a user of another role (STO-05)", :aggregate_failures do
    create(:user, :administrator, email_address: "dispatcher@example.com")

    expect { result }.to raise_error(DemoData::Conflict,
                                     "dispatcher@example.com has the role administrator, not dispatcher; nothing loaded")
    expect([ GuardedSite.count, User.count, Call.count ]).to eq([ 4, 1, 0 ])
  end

  it "loads nothing when a demo contract number belongs to another site (STO-05)", :aggregate_failures do
    create(:guarded_site, contract_number: "C-00017", name: "Own Site")

    expect { result }.to raise_error(DemoData::Conflict, "C-00017 belongs to Own Site, not to Demo Office 7; nothing loaded")
    expect([ GuardedSite.count, User.count, Call.count ]).to eq([ 5, 0, 0 ])
  end

  it "adds nothing and gives no password the second time", :aggregate_failures do
    result
    again = described_class.new.call

    expect([ again.sites, again.passwords, again.calls ]).to eq([ 0, {}, 0 ])
    expect([ GuardedSite.count, User.count, Call.count ]).to eq([ 12, 3, 150 ])
  end
end
