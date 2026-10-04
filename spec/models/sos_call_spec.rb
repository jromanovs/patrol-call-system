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
    expect(call.errors.full_messages).to include("Site must exist", "Registered by must exist")
  end

  it "asks for the car that raised it, and for a place that is whole and on the earth, or absent", :aggregate_failures do
    expect(build(:sos_call, raised_by: nil)).not_to be_valid
    expect(build(:sos_call, latitude: nil, longitude: nil, accuracy: nil)).to be_valid
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

    it "registers nothing for a place off the earth or half a place", :aggregate_failures do
      expect(described_class.signal(car, { latitude: 91.0, longitude: 24.1, accuracy: 5 })).to be_nil
      expect(described_class.signal(car, { latitude: 56.95, longitude: nil, accuracy: 5 })).to be_nil
      expect(described_class.count).to eq(0)
    end

    it "registers a call without a place when none is given, by the user who asked", :aggregate_failures do
      user = create(:user, :crew, patrol_car: car)
      call = described_class.signal(car, {}, by: user)

      expect(call).to have_attributes(latitude: nil, longitude: nil, placed_at: nil, signals: 1, registered_by: user)
      expect([ call.placed?, call.destination, call.place_detail ]).to eq([ false, nil, "Place unknown" ])
    end

    it "keeps who registered the call when a further signal comes from another phone" do
      first = create(:user, :crew, patrol_car: car)
      described_class.signal(car, place, by: first)

      expect(described_class.signal(car, place, by: create(:user, :crew, patrol_car: car)).registered_by).to eq(first)
    end

    it "tells how well the place is known: by its accuracy, by its age, or not at all", :aggregate_failures do
      travel_to(Time.zone.local(2026, 10, 3, 19, 47)) do
        fresh = described_class.signal(car, place)
        old = described_class.signal(helper, place.merge(placed_at: 12.minutes.ago, accuracy: nil))

        expect(fresh.place_detail).to eq("Position accuracy 12 m")
        expect(old.place_detail).to eq("Last position of the car, at 19:35")
        # A position of another day is told with its day.
        old.update!(placed_at: 2.days.ago, accuracy: 20)
        expect(old.place_detail).to eq("Last position of the car, at 01.10.2026 19:47 · accuracy 20 m")
      end
    end

    it "never takes an older place over a newer one", :aggregate_failures do
      travel_to(Time.zone.local(2026, 10, 3, 19, 47)) do
        call = described_class.signal(car, place)
        described_class.signal(car, { latitude: 56.9, longitude: 24.2, accuracy: 30, placed_at: 12.minutes.ago })
        expect(call.reload).to have_attributes(latitude: 56.95, accuracy: 12, signals: 2, placed_at: Time.current)

        travel(3.minutes)
        described_class.signal(car, { latitude: 56.9, longitude: 24.2, accuracy: 30, placed_at: 1.minute.ago })
        expect(call.reload).to have_attributes(latitude: 56.9, accuracy: 30, signals: 3)
      end
    end

    it "knows a place on the earth from one that is not", :aggregate_failures do
      expect(described_class.on_earth?(latitude: 56.95, longitude: 24.1)).to be(true)
      expect([ { latitude: 91.0, longitude: 24.1 }, { latitude: nil, longitude: nil }, {} ].map { |one| described_class.on_earth?(one) })
        .to eq([ false, false, false ])
    end

    it "counts a signal that came at the same moment as another in the call of the first", :aggregate_failures do
      first = described_class.signal(car, place)
      # The second signal looked for the car's call before the first was saved.
      looked = 0
      allow(described_class).to receive(:active_of).and_wrap_original do |original, asking|
        (looked += 1) == 1 ? described_class.new(raised_by: asking) : original.call(asking)
      end

      expect(described_class.signal(car, place)).to eq(first)
      expect([ described_class.count, first.reload.signals ]).to eq([ 1, 2 ])
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

  it "is closed only with an outcome of its own, and no other call with Help given (UPD-09)", :aggregate_failures do
    call = create(:sos_call, raised_by: car)
    CallStep.new(call, dispatcher).dispatch(helper)
    CallStep.new(call, dispatcher).arrive
    expect { CallStep.new(call, dispatcher).close("intrusion_confirmed", nil) }
      .to raise_error(CallStep::Refused, "Outcome is not one of a crew's SOS")
    expect(call.reload.status).to eq("on_scene")

    alarm = create(:alarm_call, guarded_site: create(:guarded_site), status: :on_scene, patrol_car: create(:patrol_car))
    expect { CallStep.new(alarm, dispatcher).close("help_given", nil) }
      .to raise_error(CallStep::Refused, "Outcome is only for a crew's SOS")
  end

  it "asks for the time of its last signal" do
    expect(build(:sos_call, signalled_at: nil)).not_to be_valid
  end

  it "is refused by the database without what its kind needs (STO-04)", :aggregate_failures do
    call = create(:sos_call, raised_by: car)
    alarm = create(:alarm_call, guarded_site: create(:guarded_site))

    # Each refusal in a transaction of its own, which it ends.
    expect { described_class.transaction(requires_new: true) { call.update_columns(latitude: nil) } }
      .to raise_error(ActiveRecord::StatementInvalid, /calls_sos_place/)
    expect { described_class.transaction(requires_new: true) { alarm.update_columns(guarded_site_id: nil) } }
      .to raise_error(ActiveRecord::StatementInvalid, /calls_site/)
  end

  describe "the strips of the open pages (DYN-19)" do
    it "are sent with the signal, as the pages draw them" do
      expect { described_class.signal(car, place) }.to have_broadcasted_to("sos").with { |stream|
        expect(stream).to include('target="sos-strips"', "SOS from P-12", "Position accuracy 12 m", "Acknowledge")
      }
    end

    it "are sent again only when a strip changes", :aggregate_failures do
      call = create(:sos_call, raised_by: car)

      expect { call.update!(description: "Yard of the tyre shop") }.not_to have_broadcasted_to("sos")
      expect { call.acknowledge(dispatcher) }.to have_broadcasted_to("sos")
      expect { call.update!(priority: :high) }.not_to have_broadcasted_to("sos")
    end
  end

  it "counts in the statistics by its outcome, and in no site's false alarms (CALC-01, CALC-04)", :aggregate_failures do
    create(:sos_call, raised_by: car, status: :closed, outcome: :false_alarm, closed_at: Time.current)
    statistics = CallStatistics.new(Call.all)

    expect(statistics.by_outcome.to_h).to include("false_alarm" => 1, "help_given" => 0)
    expect([ statistics.false_alarms.share, statistics.false_alarm_sites ]).to eq([ 100.0, [] ])
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

  it "goes with the old calls a clean-up deletes, by its kind too (DEL-07)" do
    old = create(:sos_call, raised_by: car, status: :closed, outcome: :help_given, received_at: 26.months.ago,
                            closed_at: 26.months.ago)
    cleanup = CallCleanup.new(before: 25.months.ago.to_date, statuses: %w[ closed ], kind: "sos")

    expect(cleanup.ids).to eq([ old.id ])
  end
end
