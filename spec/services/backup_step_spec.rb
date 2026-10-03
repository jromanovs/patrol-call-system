require "rails_helper"

RSpec.describe BackupStep do
  include_context "without the seeded records"

  let(:dispatcher) { create(:user) }
  let(:first) { create(:patrol_car, call_sign: "P-03") }
  let(:further) { create(:patrol_car, call_sign: "P-15") }
  let(:site) { create(:guarded_site, name: "Demo Shop 10") }
  let(:call) { create(:alarm_call, guarded_site: site).tap { |one| CallStep.new(one, dispatcher).dispatch(first) } }

  def sent = described_class.new(call, dispatcher).send_car(further)

  describe "#send_car (UPD-14, BR-22)" do
    it "sends a free car to a call that has its car, and tells its crew", :aggregate_failures do
      freeze_time
      backup = nil
      expect { backup = sent }.to have_enqueued_job(CrewNoticeJob).with(call, further)

      expect(backup).to have_attributes(call:, patrol_car: further, sent_by: dispatcher, sent_at: Time.current,
                                        accepted_at: nil, arrived_at: nil, released_at: nil, state: "sent")
      expect([ further.reload.status, call.reload.patrol_car ]).to eq([ "dispatched", first ])
    end

    it "is refused for a call without its car, and for a finished one", :aggregate_failures do
      waiting = create(:alarm_call, guarded_site: site)
      expect { described_class.new(waiting, dispatcher).send_car(further) }
        .to raise_error(CallStep::Refused, "The call has no car yet; dispatch one first")

      CallStep.new(call, dispatcher).cancel(nil)
      expect { sent }.to raise_error(CallStep::Refused, "The call is cancelled; no further steps")
      expect([ Backup.count, further.reload.status ]).to eq([ 0, "available" ])
    end

    it "is refused for a car that is not free, as the call's own car or one sent already", :aggregate_failures do
      sent

      [ first, further, create(:patrol_car, call_sign: "P-21", status: :out_of_service) ].each do |car|
        expect { described_class.new(call, dispatcher).send_car(car) }
          .to raise_error(CallStep::Unavailable, "Car #{car.call_sign} is not available")
      end
      expect(Backup.count).to eq(1)
    end

    it "never sends the car that asked for help to its own SOS" do
      asking = create(:patrol_car, call_sign: "P-12")
      sos = create(:sos_call, raised_by: asking)
      CallStep.new(sos, dispatcher).dispatch(first)

      expect { described_class.new(sos, dispatcher).send_car(asking) }
        .to raise_error(CallStep::Refused, "P-12 raised this call and cannot be sent to it")
    end
  end

  describe "the steps of a further car (UPD-15)" do
    def crew = further.crew.first || create(:user, :crew, patrol_car: further)

    def backup = call.backups.first || sent

    it "accepts once; a second acceptance changes nothing" do
      accepted = Time.zone.local(2026, 10, 3, 19, 56)
      travel_to(accepted) { described_class.new(call, crew).accept(backup) }
      travel_to(accepted + 1.minute) { described_class.new(call, crew).accept(backup) }

      expect(backup.reload).to have_attributes(accepted_at: accepted, state: "on-the-way")
    end

    it "arrives, which is the acceptance too, and keeps where the crew's phone was", :aggregate_failures do
      freeze_time
      described_class.new(call, crew).arrive(backup, position: { latitude: site.address.latitude.to_s,
                                                                 longitude: site.address.longitude.to_s, accuracy: "8" })

      expect(backup.reload).to have_attributes(arrived_at: Time.current, accepted_at: Time.current, state: "on-site")
      expect(further.reload.status).to eq("on_scene")
      expect(backup.arrival_position).to have_attributes(step: "arrival", user: crew, distance: 0, accuracy: 8)
      # The call's own arrival is that of its first car.
      expect([ call.reload.status, call.arrival_position ]).to eq([ "dispatched", nil ])
    end

    it "arrives once: a second Arrived changes neither the time nor the position", :aggregate_failures do
      arrived = Time.zone.local(2026, 10, 3, 19, 56)
      place = { latitude: site.address.latitude.to_s, longitude: site.address.longitude.to_s }
      travel_to(arrived) { described_class.new(call, crew).arrive(backup, position: place) }
      travel_to(arrived + 9.minutes) { described_class.new(call, dispatcher).arrive(backup, position: place) }

      expect(backup.reload.arrived_at).to eq(arrived)
      expect(call.step_positions.where(backup:).count).to eq(1)
    end

    it "is released by the dispatcher, and takes no step after that", :aggregate_failures do
      freeze_time
      described_class.new(call, dispatcher).release(backup)

      expect([ backup.reload.released_at, further.reload.status ]).to eq([ Time.current, "available" ])
      expect { described_class.new(call, crew).arrive(backup) }.to raise_error(CallStep::Refused, "P-15 is released from this call")
    end
  end

  describe "the end of the call (UPD-16)" do
    it "frees every further car when the call is closed or cancelled", :aggregate_failures do
      freeze_time
      backup = sent
      CallStep.new(call, dispatcher).cancel("Client called back")

      expect([ backup.reload.released_at, further.reload.status, first.reload.status ]).to eq([ Time.current, "available", "available" ])

      other = create(:alarm_call, guarded_site: site)
      CallStep.new(other, dispatcher).dispatch(first)
      described_class.new(other, dispatcher).send_car(further)
      CallStep.new(other, dispatcher).arrive
      CallStep.new(other, dispatcher).close("false_alarm", nil)
      expect([ other.backups.sole.released_at, further.reload.status ]).to eq([ Time.current, "available" ])
    end

    it "leaves a car released earlier as it was" do
      backup = sent
      released = 5.minutes.ago
      travel_to(released) { described_class.new(call, dispatcher).release(backup) }
      CallStep.new(call, dispatcher).cancel(nil)

      expect(backup.reload.released_at).to eq(released.change(usec: 0))
    end
  end

  describe "the response time (2.10, CALC-02)" do
    it "counts to the first car that arrived, the call's own or a further one", :aggregate_failures do
      received = Time.zone.local(2026, 10, 3, 19, 47)
      one = travel_to(received) { create(:alarm_call, guarded_site: site) }
      travel_to(received + 1.minute) do
        CallStep.new(one, dispatcher).dispatch(first)
        described_class.new(one, dispatcher).send_car(further)
      end
      travel_to(received + 6.minutes) { described_class.new(one, dispatcher).arrive(one.backups.sole) }
      travel_to(received + 10.minutes) { CallStep.new(one, dispatcher).arrive }

      expect(one.reload.response_minutes).to eq(6.0)
      statistics = CallStatistics.new(Call.where(id: one.id))
      expect([ statistics.arrivals, statistics.response ]).to eq([ 1, 6.0 ])
    end

    it "counts a call that only a further car reached, and orders the list by it", :aggregate_failures do
      received = Time.zone.local(2026, 10, 3, 19, 47)
      slow, quick = travel_to(received) { create_list(:alarm_call, 2, guarded_site: site) }
      travel_to(received + 1.minute) do
        CallStep.new(slow, dispatcher).dispatch(first)
        CallStep.new(quick, dispatcher).dispatch(create(:patrol_car))
        described_class.new(quick, dispatcher).send_car(further)
      end
      travel_to(received + 4.minutes) { described_class.new(quick, dispatcher).arrive(quick.backups.sole) }
      travel_to(received + 9.minutes) { CallStep.new(slow, dispatcher).arrive }

      statistics = CallStatistics.new(Call.where(id: [ slow.id, quick.id ]))
      expect([ statistics.arrivals, statistics.response ]).to eq([ 2, 6.5 ])
      expect(CallFilter.new(sort: "response").results.to_a).to eq([ quick, slow ])
    end

    it "gives each car its own arrivals in the response time by car (CALC-02)" do
      received = Time.zone.local(2026, 10, 3, 19, 47)
      one = travel_to(received) { create(:alarm_call, guarded_site: site) }
      travel_to(received + 1.minute) do
        CallStep.new(one, dispatcher).dispatch(first)
        described_class.new(one, dispatcher).send_car(further)
      end
      travel_to(received + 6.minutes) { described_class.new(one, dispatcher).arrive(one.backups.sole) }
      travel_to(received + 10.minutes) { CallStep.new(one, dispatcher).arrive }

      by_car = CallStatistics.new(Call.where(id: one.id)).response_by_car.to_h { |car, *values| [ car.call_sign, values ] }
      expect(by_car).to eq("P-03" => [ 1, 10.0 ], "P-15" => [ 1, 6.0 ])
    end
  end

  describe "what keeps the records together (BR-9, DEL-07)" do
    it "keeps a car that was a further car from being deleted, and deletes the further cars with an old call",
       :aggregate_failures do
      sent
      CallStep.new(call, dispatcher).cancel(nil)
      expect(further.reload.destroy).to be(false)
      expect(further.kept_reason).to eq("Car has 1 call and cannot be deleted; put it out of service instead")

      # With where a further crew's phone was, which points at the further car.
      call.step_positions.create!(step: :arrival, user: dispatcher, backup: call.backups.sole)
      call.update_columns(received_at: 40.days.ago)
      cleanup = CallCleanup.new(before: 30.days.ago.to_date, statuses: %w[ cancelled ])
      cleanup.delete(CallCleanup.fingerprint(cleanup.ids))
      expect([ Call.count, Backup.count ]).to eq([ 0, 0 ])
    end
  end
end
