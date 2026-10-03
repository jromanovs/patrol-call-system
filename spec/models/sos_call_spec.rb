require "rails_helper"

RSpec.describe SosCall do
  include_context "without the seeded records"

  let(:car) { create(:patrol_car, call_sign: "P-12", district: :north) }
  let(:helper) { create(:patrol_car, call_sign: "P-03") }
  let(:dispatcher) { create(:user) }
  let(:place) { { latitude: 56.95, longitude: 24.1, accuracy: 12 } }

  it "is a call raised by a crew, critical, without a site and without a registering user (BR-21)", :aggregate_failures do
    call = create(:sos_call, raised_by: car)

    expect(described_class.superclass).to eq(Call)
    expect(call).to have_attributes(guarded_site: nil, registered_by: nil, priority: "critical", status: "pending")
  end

  it "leaves the other calls with their site and their registering user", :aggregate_failures do
    call = build(:alarm_call, guarded_site: nil, registered_by: nil)

    expect(call).not_to be_valid
    expect(call.errors.full_messages).to include("Guarded site must exist", "Registered by must exist")
  end

  it "asks for the car that raised it and for a place on the earth", :aggregate_failures do
    expect(build(:sos_call, raised_by: nil)).not_to be_valid
    expect(build(:sos_call, latitude: nil)).not_to be_valid
    expect(build(:sos_call, latitude: 91)).not_to be_valid
    expect(build(:sos_call, longitude: 181)).not_to be_valid
    expect(build(:sos_call, signals: 0)).not_to be_valid
  end

  it "describes itself where a call at a site names its site", :aggregate_failures do
    call = build(:sos_call, raised_by: car)

    expect([ call.summary, call.detail, call.place, call.title ])
      .to eq([ "Crew's SOS", "From P-12", "Crew of P-12", "Crew's SOS from P-12" ])
    expect([ call.district, call.destination ]).to eq([ "north", call ])
  end

  it "leaves a call at a site described by the site", :aggregate_failures do
    site = create(:guarded_site, name: "Demo Shop 10", district: :east)
    call = build(:alarm_call, guarded_site: site, alarm_type: :intrusion)

    expect([ call.place, call.title ]).to eq([ "Demo Shop 10", "Alarm: intrusion at Demo Shop 10" ])
    expect([ call.district, call.destination ]).to eq([ "east", site.address ])
  end

  describe ".signal (ADD-11)" do
    it "registers a call at the place the signal came from" do
      freeze_time
      call = described_class.signal(car, place)

      expect(call).to have_attributes(raised_by: car, latitude: 56.95, longitude: 24.1, accuracy: 12, signals: 1,
                                      signalled_at: Time.current, received_at: Time.current, priority: "critical")
    end

    it "takes a further signal into the active call: its place, its time, its count, and to be acknowledged again",
       :aggregate_failures do
      first = Time.zone.local(2026, 10, 3, 19, 47)
      call = travel_to(first) { described_class.signal(car, place) }
      call.acknowledge(dispatcher)
      again = travel_to(first + 1.minute) { described_class.signal(car, place.merge(latitude: 56.96, accuracy: nil)) }

      expect(again).to eq(call)
      expect(described_class.count).to eq(1)
      expect(call.reload).to have_attributes(latitude: 56.96, accuracy: nil, signals: 2, received_at: first,
                                             signalled_at: first + 1.minute, acknowledged_at: nil, acknowledged_by: nil)
    end

    it "registers a new call once the earlier one is finished" do
      described_class.signal(car, place).update!(status: :cancelled, closed_at: Time.current)

      expect(described_class.signal(car, place)).to have_attributes(status: "pending", signals: 1)
    end

    it "registers nothing without a place on the earth", :aggregate_failures do
      expect(described_class.signal(car, latitude: nil, longitude: nil, accuracy: nil)).to be_nil
      expect(described_class.signal(car, latitude: 91.0, longitude: 24.1, accuracy: 5)).to be_nil
      expect(described_class.count).to eq(0)
    end

    it "keeps the calls of two cars apart" do
      described_class.signal(car, place)
      described_class.signal(helper, place)

      expect(described_class.pluck(:raised_by_id)).to contain_exactly(car.id, helper.id)
    end
  end

  describe "the acknowledgement (UPD-13)" do
    let(:call) { create(:sos_call, raised_by: car) }

    it "is made once, by who saw the signal first", :aggregate_failures do
      seen = Time.zone.local(2026, 10, 3, 19, 49)
      travel_to(seen) { call.acknowledge(dispatcher) }
      travel_to(seen + 1.minute) { expect(call.acknowledge(create(:user))).to be(true) }

      expect(call.reload).to have_attributes(acknowledged_at: seen, acknowledged_by: dispatcher)
    end

    it "comes with the sending of a car" do
      freeze_time
      CallStep.new(call, dispatcher).dispatch(helper)

      expect(call.reload).to have_attributes(acknowledged_at: Time.current, acknowledged_by: dispatcher)
    end

    it "stays as made before the car was sent" do
      first = create(:user)
      call.acknowledge(first)
      CallStep.new(call, dispatcher).dispatch(helper)

      expect(call.reload.acknowledged_by).to eq(first)
    end

    it "lists the active calls not acknowledged, the oldest first" do
      old = create(:sos_call, received_at: 5.minutes.ago)
      create(:sos_call).acknowledge(dispatcher)
      create(:sos_call, status: :cancelled)

      expect(described_class.unacknowledged).to eq([ old, call ])
    end
  end

  it "cannot take the car that raised it (UPD-06)", :aggregate_failures do
    call = create(:sos_call, raised_by: car)

    expect { CallStep.new(call, dispatcher).dispatch(car) }
      .to raise_error(CallStep::Refused, "P-12 raised this call and cannot be sent to it")
    expect([ call.reload.status, car.reload.status ]).to eq(%w[ pending available ])
  end

  it "is closed with an outcome of its own (UPD-09)", :aggregate_failures do
    expect(build(:sos_call).outcome_choices).to eq(%w[ help_given false_alarm other ])
    expect(build(:alarm_call).outcome_choices)
      .to eq(%w[ false_alarm intrusion_confirmed fire_confirmed technical_fault other ])
  end

  it "measures the crew's Arrived from the place of the signal (CRW-07)" do
    call = create(:sos_call, raised_by: car, latitude: 56.95, longitude: 24.1)
    CallStep.new(call, dispatcher).dispatch(helper)
    CallStep.new(call, create(:user, :crew, patrol_car: helper)).arrive(position: { latitude: "56.95", longitude: "24.1" })

    expect(call.arrival_position.distance).to eq(0)
  end

  it "names who asked when the car sent to help cannot go out of service (BR-6)" do
    travel_to(Time.zone.local(2026, 10, 3, 19, 50)) do
      call = create(:sos_call, raised_by: car, received_at: 3.minutes.ago)
      CallStep.new(call, dispatcher).dispatch(helper)
      helper.status = "out_of_service"
      helper.valid?
    end

    expect(helper.errors[:status])
      .to include("cannot be out of service: active call at Crew of P-12, received 03.10.2026 19:47")
  end

  it "keeps a car that raised a call from being deleted (BR-9)", :aggregate_failures do
    create(:sos_call, raised_by: car)

    expect(car.destroy).to be(false)
    expect(car.kept_reason).to eq("Car has 1 call and cannot be deleted; put it out of service instead")
  end
end
