require "rails_helper"

RSpec.describe CallStep do
  subject(:step) { described_class.new(call, dispatcher) }

  include_context "without the seeded records"

  let(:dispatcher) { create(:user) }
  let(:call) { create(:alarm_call, received_at: Time.zone.local(2026, 10, 1, 9, 0)) }
  let(:car) { create(:patrol_car, call_sign: "P-12") }

  def at(minute, &) = travel_to(Time.zone.local(2026, 10, 1, 9, minute), &)

  describe "#dispatch (UPD-06)" do
    it "sends the car: call and car dispatched, time and dispatcher kept", :aggregate_failures do
      at(5) { step.dispatch(car) }

      expect(call.reload).to have_attributes(status: "dispatched", patrol_car: car, dispatched_by: dispatcher,
                                             dispatched_at: Time.zone.local(2026, 10, 1, 9, 5))
      expect(car.reload).to be_dispatched
    end

    it "has the car's crew told on their phones once the dispatch is saved (CRW-04)" do
      expect { step.dispatch(car) }.to have_enqueued_job(CrewNoticeJob).with(call)
    end

    it "plans the first reminder of the crew a minute later (CRW-06)" do
      at(5) do
        expect { step.dispatch(car) }.to have_enqueued_job(CrewReminderJob).with(call, 1).at(Time.zone.local(2026, 10, 1, 9, 6))
      end
    end

    it "refuses a car that is not free and changes nothing (UPD-07, BR-3)", :aggregate_failures do
      car.out_of_service!

      expect { step.dispatch(car) }.to raise_error(CallStep::Refused, "Car P-12 is not available")
      expect(call.reload).to be_pending
    end

    it "tells no crew of a refused dispatch (CRW-04)" do
      car.out_of_service!

      expect { expect { step.dispatch(car) }.to raise_error(CallStep::Refused) }.not_to have_enqueued_job(CrewNoticeJob)
    end

    it "refuses a car already on another call (BR-4)" do
      described_class.new(create(:alarm_call), dispatcher).dispatch(car)

      expect { step.dispatch(car.reload) }.to raise_error(CallStep::Refused, "Car P-12 is not available")
    end

    it "leaves the call as it was when the car cannot be saved (STO-02)", :aggregate_failures do
      allow(car).to receive(:update!).and_raise(ActiveRecord::RecordInvalid.new(car))

      expect { step.dispatch(car) }.to raise_error(CallStep::Refused)
      expect(call.reload).to have_attributes(status: "pending", patrol_car: nil, dispatched_at: nil)
    end
  end

  describe "#accept (UPD-12)" do
    it "records the acceptance; the car stays sent", :aggregate_failures do
      at(5) { step.dispatch(car) }
      message = at(7) { step.accept }

      expect(call.reload).to have_attributes(status: "accepted", accepted_at: Time.zone.local(2026, 10, 1, 9, 7))
      expect(car.reload).to be_dispatched
      expect(message).to eq("Call accepted by P-12")
    end

    it "refuses a call not sent yet" do
      expect { step.accept }.to raise_error(CallStep::Refused, "Not possible for a pending call; possible now: Dispatch, Cancel")
    end

    it "takes an acceptance again, from a second phone or a second tap, as done already", :aggregate_failures do
      at(5) { step.dispatch(car) }
      at(6) { step.accept }

      expect(at(7) { step.accept }).to eq("Call accepted by P-12")
      expect(call.reload.accepted_at).to eq(Time.zone.local(2026, 10, 1, 9, 6))
    end
  end

  describe "#arrive (UPD-08)" do
    it "puts call and car on scene and tells the response time", :aggregate_failures do
      at(5) { step.dispatch(car) }
      message = at(17) { step.arrive }

      expect(call.reload).to have_attributes(status: "on_scene", arrived_at: Time.zone.local(2026, 10, 1, 9, 17))
      expect(car.reload).to be_on_scene
      expect(message).to eq("Arrival recorded; response time 17.0 min")
    end

    it "takes an arrival without an acceptance as the acceptance too (UPD-08)" do
      at(5) { step.dispatch(car) }
      at(17) { step.arrive }

      expect(call.reload.accepted_at).to eq(Time.zone.local(2026, 10, 1, 9, 17))
    end

    it "keeps the time of an earlier acceptance and arrives from it", :aggregate_failures do
      at(5) { step.dispatch(car) }
      at(6) { step.accept }
      at(17) { step.arrive }

      expect(call.reload).to have_attributes(status: "on_scene", accepted_at: Time.zone.local(2026, 10, 1, 9, 6))
    end
  end

  describe "the position of the crew's phone (CRW-07)" do
    let(:crew) { create(:user, :crew, patrol_car: car) }
    let(:crew_step) { described_class.new(call, crew) }

    before { step.dispatch(car) }

    it "keeps where the phone was at the arrival, with the distance from the site" do
      crew_step.arrive(position: { latitude: "56.9522", longitude: "24.104642", accuracy: "12" })

      expect(call.step_positions.sole)
        .to have_attributes(step: "arrival", user: crew, latitude: 56.9522, longitude: 24.104642, accuracy: 12, distance: 111)
    end

    it "keeps where the phone was at the closing" do
      crew_step.arrive(position: {})
      crew_step.close("other", "", position: { latitude: "56.9512", longitude: "24.104642", accuracy: "5" })

      expect(call.step_positions.closing.sole).to have_attributes(user: crew, accuracy: 5, distance: 0)
    end

    it "keeps the position unknown when the phone gave none, or none on the earth", :aggregate_failures do
      crew_step.arrive(position: { latitude: "200", longitude: "x", accuracy: "12" })

      expect(call.step_positions.sole).to have_attributes(step: "arrival", latitude: nil, longitude: nil, accuracy: nil,
                                                          distance: nil)
      expect(call.reload).to be_on_scene
    end

    it "keeps the accuracy unknown when the phone sent one beyond the earth, and the steps go", :aggregate_failures do
      crew_step.arrive(position: { latitude: "56.9522", longitude: "24.104642", accuracy: "1e10" })
      crew_step.close("other", "", position: { latitude: "56.9522", longitude: "24.104642", accuracy: "1e400" })

      expect(call.step_positions.order(:step).pluck(:accuracy, :distance)).to eq([ [ nil, 111 ], [ nil, 111 ] ])
      expect(call.reload).to be_closed
    end

    it "keeps no position for a step without one, such as the dispatcher's" do
      step.arrive

      expect(call.step_positions).to be_empty
    end
  end

  describe "#close (UPD-09)" do
    before do
      step.dispatch(car)
      step.arrive
    end

    it "closes with an outcome, keeps the note apart from the description and frees the car", :aggregate_failures do
      call.update!(description: "Back door")
      at(40) { step.close("false_alarm", "Sensor fault") }

      expect(call.reload).to have_attributes(status: "closed", outcome: "false_alarm",
                                             closed_at: Time.zone.local(2026, 10, 1, 9, 40),
                                             description: "Back door", closing_note: "Sensor fault", cancellation_reason: nil)
      expect(car.reload).to be_available
    end

    it "keeps no note of a closing without one" do
      step.close("false_alarm", " ")

      expect(call.reload).to have_attributes(status: "closed", closing_note: nil)
    end

    it "refuses a note longer than a description may be", :aggregate_failures do
      expect { step.close("false_alarm", "n" * 1001) }
        .to raise_error(CallStep::Refused, "Closing note is too long (maximum is 1000 characters)")
      expect(call.reload).to be_on_scene
    end

    it "refuses to close without an outcome", :aggregate_failures do
      expect { step.close("", "") }.to raise_error(CallStep::Refused, "Choose an outcome to close the call")
      expect(call.reload).to be_on_scene
    end
  end

  describe "#cancel (UPD-10)" do
    it "cancels a pending call and keeps the reason apart from the description" do
      call.update!(description: "Back door")
      step.cancel("Client called back")

      expect(call.reload).to have_attributes(status: "cancelled", description: "Back door",
                                             cancellation_reason: "Client called back", closing_note: nil)
    end

    it "refuses a reason longer than a description may be", :aggregate_failures do
      expect { step.cancel("r" * 1001) }
        .to raise_error(CallStep::Refused, "Cancellation reason is too long (maximum is 1000 characters)")
      expect(call.reload).to be_pending
    end

    it "frees the car of an accepted call", :aggregate_failures do
      step.dispatch(car)
      step.accept
      step.cancel("")

      expect(call.reload).to be_cancelled
      expect(car.reload).to be_available
    end

    it "frees the car of a dispatched call", :aggregate_failures do
      step.dispatch(car)
      step.cancel("")

      expect(call.reload).to have_attributes(status: "cancelled", description: nil)
      expect(call.closed_at).to be_present
      expect(car.reload).to be_available
    end
  end

  describe "a step that does not fit the status (UPD-11)" do
    it "lists the steps allowed now and changes nothing", :aggregate_failures do
      expect { step.close("false_alarm", "") }
        .to raise_error(CallStep::Refused, "Not possible for a pending call; possible now: Dispatch, Cancel")
      expect { step.arrive }.to raise_error(CallStep::Refused, /possible now: Dispatch, Cancel/)
      expect(call.reload).to be_pending
    end

    it "allows nothing after closing" do
      step.cancel("")

      expect { step.arrive }.to raise_error(CallStep::Refused, "The call is cancelled; no further steps")
    end
  end
end
