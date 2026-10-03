require "rails_helper"

# STO-03, BR-4: two dispatchers send the same free car at the same moment —
# as a further car to two calls, or as a further car to one and as the own
# car of another. The threads need their own committed records, so this
# group runs without the transaction of every example and cleans up after
# itself.
RSpec.describe BackupStep, "#send_car" do
  self.use_transactional_tests = false

  let(:dispatcher) { create(:user) }
  let(:car) { create(:patrol_car, call_sign: "P-79") }
  let(:firsts) { [ create(:patrol_car, call_sign: "P-80"), create(:patrol_car, call_sign: "P-81") ] }
  let(:calls) { create_list(:alarm_call, 3) }

  before { calls.first(2).zip(firsts).each { |call, first| CallStep.new(call, dispatcher).dispatch(first) } }

  after do
    Backup.where(call_id: calls.map(&:id)).delete_all
    Call.where(id: calls.map(&:id)).delete_all
    GuardedSite.where(id: calls.map(&:guarded_site_id)).delete_all
    Address.where(code: 900_000_000..).where.missing(:guarded_sites).delete_all
    [ car, *firsts ].each(&:destroy)
    User.where(id: [ dispatcher.id, *calls.map(&:registered_by_id) ]).delete_all
  end

  # Runs the steps at the same moment, each on a connection of its own, and
  # gives what each came to.
  def together(steps)
    start = Concurrent::CountDownLatch.new(1)
    threads = steps.map do |step|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          start.wait
          step.call
          :sent
        rescue CallStep::Refused => error
          error.message
        end
      end
    end
    start.count_down
    threads.map(&:value)
  end

  def further(call) = -> { described_class.new(Call.find(call.id), dispatcher).send_car(PatrolCar.find(car.id)) }

  it "lets one of two sendings as a further car through and refuses the other", :aggregate_failures do
    expect(together(calls.first(2).map { |call| further(call) })).to contain_exactly(:sent, "Car P-79 is not available")
    expect(Backup.where(patrol_car_id: car.id, released_at: nil).count).to eq(1)
  end

  it "lets one of a dispatch and a sending as a further car through and refuses the other", :aggregate_failures do
    dispatch = -> { CallStep.new(Call.find(calls.last.id), dispatcher).dispatch(PatrolCar.find(car.id)) }

    expect(together([ dispatch, further(calls.first) ])).to contain_exactly(:sent, "Car P-79 is not available")
    expect(Call.where(patrol_car_id: car.id).count + Backup.where(patrol_car_id: car.id).count).to eq(1)
  end
end
