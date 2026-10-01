require "rails_helper"

# STO-03: two dispatchers send the same car at the same moment. The threads
# need their own committed records, so this group runs without the
# transaction of every example and cleans up after itself.
RSpec.describe CallStep, "#dispatch" do
  self.use_transactional_tests = false

  let(:dispatcher) { create(:user) }
  let(:car) { create(:patrol_car, call_sign: "P-77") }
  let(:calls) { create_list(:alarm_call, 2) }

  after do
    Call.where(id: calls.map(&:id)).delete_all
    GuardedSite.where(id: calls.map(&:guarded_site_id)).delete_all
    Address.where(code: 900_000_000..).where.missing(:guarded_sites).delete_all
    car.destroy
    User.where(id: [ dispatcher.id, *calls.map(&:registered_by_id) ]).delete_all
  end

  it "lets one of two dispatchers taking the same car at once through and refuses the other (STO-03, BR-4)", :aggregate_failures do
    start = Concurrent::CountDownLatch.new(1)
    threads = calls.map do |call|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          start.wait
          described_class.new(Call.find(call.id), dispatcher).dispatch(PatrolCar.find(car.id))
          :dispatched
        rescue CallStep::Refused => error
          error.message
        end
      end
    end
    start.count_down

    expect(threads.map(&:value)).to contain_exactly(:dispatched, "Car P-77 is not available")
    expect(Call.where(patrol_car_id: car.id, status: Call::ACTIVE).count).to eq(1)
  end
end
