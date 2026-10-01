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

    it "refuses a car that is not free and changes nothing (UPD-07, BR-3)", :aggregate_failures do
      car.out_of_service!

      expect { step.dispatch(car) }.to raise_error(CallStep::Refused, "Car P-12 is not available")
      expect(call.reload).to be_pending
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

  describe "#arrive (UPD-08)" do
    it "puts call and car on scene and tells the response time", :aggregate_failures do
      at(5) { step.dispatch(car) }
      message = at(17) { step.arrive }

      expect(call.reload).to have_attributes(status: "on_scene", arrived_at: Time.zone.local(2026, 10, 1, 9, 17))
      expect(car.reload).to be_on_scene
      expect(message).to eq("Arrival recorded; response time 17.0 min")
    end
  end

  describe "#close (UPD-09)" do
    before do
      step.dispatch(car)
      step.arrive
    end

    it "closes with an outcome, adds the note and frees the car", :aggregate_failures do
      call.update!(description: "Back door")
      at(40) { step.close("false_alarm", "Sensor fault") }

      expect(call.reload).to have_attributes(status: "closed", outcome: "false_alarm",
                                             closed_at: Time.zone.local(2026, 10, 1, 9, 40),
                                             description: "Back door\nClosing note: Sensor fault")
      expect(car.reload).to be_available
    end

    it "refuses to close without an outcome", :aggregate_failures do
      expect { step.close("", "") }.to raise_error(CallStep::Refused, "Choose an outcome to close the call")
      expect(call.reload).to be_on_scene
    end
  end

  describe "#cancel (UPD-10)" do
    it "cancels a pending call with a reason" do
      step.cancel("Client called back")

      expect(call.reload).to have_attributes(status: "cancelled", description: "Cancelled: Client called back")
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
