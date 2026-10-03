require "rails_helper"

RSpec.describe PatrolCar do
  subject { build(:patrol_car) }

  describe "validations" do
    it { is_expected.to validate_uniqueness_of(:call_sign) }
    it { is_expected.to allow_value("Q-12", "ABC-123", "Z-1").for(:call_sign) }
    it { is_expected.not_to allow_value("p-12", "ABCD-1", "P-1234", "P12").for(:call_sign) }
    it { is_expected.to allow_value("ZZ-0001", "AB", "AB12-CD34Z").for(:plate_number) }
    it { is_expected.not_to allow_value("A", "AB12-CD34ZX", "AB 12").for(:plate_number) }
    it { is_expected.to validate_length_of(:model).is_at_least(2).is_at_most(50) }
    it { is_expected.to define_enum_for(:district).with_values(centre: 0, north: 1, south: 2, east: 3, west: 4) }
    it { is_expected.to define_enum_for(:status).with_values(available: 0, dispatched: 1, on_scene: 2, out_of_service: 3) }
    it { is_expected.to have_many(:calls).dependent(:restrict_with_error) }
  end

  it "shares the status-transition interface with calls (BR-5)", :aggregate_failures do
    expect(described_class.ancestors).to include(StatusTransitions)
    expect(described_class.next_statuses("available")).to eq(%w[dispatched out_of_service])
    expect(described_class.next_statuses("on_scene")).to eq(%w[available])
    car = create(:patrol_car)
    expect(car.update(status: :on_scene)).to be(false)
  end

  describe "the identifier for Traccar Client (TRK-02, BR-20)" do
    let(:car) { create(:patrol_car) }

    it "is 32 random characters, kept only as a digest with a hint", :aggregate_failures do
      key = car.issue_tracking_key

      expect(key).to match(/\A[1-9A-HJ-NP-Za-km-z]{32}\z/)
      expect(car.reload.tracking_key_digest).to eq(Digest::SHA256.hexdigest(key))
      expect(car.tracking_key_hint).to eq("#{key.first(4)}…#{key.last(4)}")
      expect(car.tracking_key_issued_at).to be_present
    end

    it "finds its car, and a new one replaces the old at once", :aggregate_failures do
      old = car.issue_tracking_key
      expect(described_class.find_by_tracking_key(old)).to eq(car)

      car.issue_tracking_key
      expect(described_class.find_by_tracking_key(old)).to be_nil
      expect([ described_class.find_by_tracking_key(""), described_class.find_by_tracking_key(nil) ]).to eq([ nil, nil ])
    end
  end

  it "starts available" do
    expect(described_class.new.status).to eq("available")
  end

  it "accepts a crew of 1 and 4 and refuses 0 and 5 (ADD-04)", :aggregate_failures do
    expect([ 1, 4 ].map { |size| build(:patrol_car, crew_size: size).valid? }).to eq([ true, true ])
    car = build(:patrol_car, crew_size: 5)
    expect(car).not_to be_valid
    expect(car.errors[:crew_size]).to eq([ "must be between 1 and 4" ])
    expect(build(:patrol_car, crew_size: 0)).not_to be_valid
  end

  it "stores the plate number in upper case, unique in any letter case", :aggregate_failures do
    car = create(:patrol_car, plate_number: " zz-0001 ")

    expect(car.plate_number).to eq("ZZ-0001")
    expect(build(:patrol_car, plate_number: "Zz-0001")).not_to be_valid
  end

  it "goes out of service only without an active call (BR-6)", :aggregate_failures do
    car = create(:patrol_car)
    call = create(:alarm_call, patrol_car: car, guarded_site: create(:guarded_site, name: "Warehouse No. 3"),
                               received_at: Time.zone.local(2026, 10, 1, 15, 32))

    expect(car.update(status: :out_of_service)).to be(false)
    expect(car.errors[:status].first).to eq("cannot be out of service: active call at Warehouse No. 3, received 01.10.2026 15:32")
    call.update_column(:status, Call.statuses[:closed])
    expect(car.reload.update(status: :out_of_service)).to be(true)
  end

  it "asks every open board to refresh after a change (DYN-02)" do
    car = create(:patrol_car)

    expect { car.update!(status: :out_of_service) }
      .to have_enqueued_job(Turbo::Streams::BroadcastStreamJob).with("board", content: a_string_including('action="refresh"'))
  end
end
