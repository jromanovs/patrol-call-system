require "rails_helper"

# STO-03, BR-4: two dispatchers send the same free car as a further car to
# two calls at the same moment. The threads need their own committed
# records, so this group runs without the transaction of every example and
# cleans up after itself.
RSpec.describe BackupStep, "#send_car" do
  self.use_transactional_tests = false

  let(:dispatcher) { create(:user) }
  let(:car) { create(:patrol_car, call_sign: "P-79") }
  let(:firsts) { [ create(:patrol_car, call_sign: "P-80"), create(:patrol_car, call_sign: "P-81") ] }
  let(:calls) { create_list(:alarm_call, 2) }

  before { calls.zip(firsts).each { |call, first| CallStep.new(call, dispatcher).dispatch(first) } }

  after do
    Backup.where(call_id: calls.map(&:id)).delete_all
    Call.where(id: calls.map(&:id)).delete_all
    GuardedSite.where(id: calls.map(&:guarded_site_id)).delete_all
    Address.where(code: 900_000_000..).where.missing(:guarded_sites).delete_all
    [ car, *firsts ].each(&:destroy)
    User.where(id: [ dispatcher.id, *calls.map(&:registered_by_id) ]).delete_all
  end

  it "lets one through and refuses the other", :aggregate_failures do
    start = Concurrent::CountDownLatch.new(1)
    threads = calls.map do |call|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          start.wait
          described_class.new(Call.find(call.id), dispatcher).send_car(PatrolCar.find(car.id))
          :sent
        rescue CallStep::Refused => error
          error.message
        end
      end
    end
    start.count_down

    expect(threads.map(&:value)).to contain_exactly(:sent, "Car P-79 is not available")
    expect(Backup.where(patrol_car_id: car.id, released_at: nil).count).to eq(1)
  end
end
