require "rails_helper"

# ADD-11, BR-21: signals of one car that meet each other, or the cancelling
# of its call. The threads need their own committed records, so this group
# runs without the transaction of every example and cleans up after itself.
RSpec.describe SosCall, ".signal" do
  self.use_transactional_tests = false

  let(:car) { create(:patrol_car, call_sign: "P-78") }
  let(:place) { { latitude: 56.95, longitude: 24.1, accuracy: 12 } }
  let!(:call) { described_class.signal(car, place) }

  after do
    Call.where(raised_by_id: car.id).delete_all
    car.destroy
  end

  def in_thread(&) = Thread.new { ActiveRecord::Base.connection_pool.with_connection(&) }

  # Cancels the call and keeps the change unsaved until released.
  def cancelling(cancelled, release)
    in_thread do
      Call.transaction do
        Call.lock.find(call.id).update!(status: :cancelled, closed_at: Time.current)
        cancelled.count_down
        release.wait(5)
      end
    end
  end

  it "counts each of two signals that come at once" do
    start = Concurrent::CountDownLatch.new(1)
    threads = Array.new(2) do
      in_thread do
        start.wait
        described_class.signal(PatrolCar.find(car.id), place)
      end
    end
    start.count_down
    threads.each(&:join)

    expect(described_class.where(raised_by_id: car.id).pluck(:signals)).to eq([ 3 ])
  end

  it "registers a new call for a signal that comes while the active one is being cancelled", :aggregate_failures do
    cancelled = Concurrent::CountDownLatch.new(1)
    release = Concurrent::CountDownLatch.new(1)
    canceller = cancelling(cancelled, release)
    cancelled.wait(5)
    signaller = in_thread { described_class.signal(PatrolCar.find(car.id), place) }
    # The signal has asked for the call and waits for the cancelling to end.
    sleep 0.3
    release.count_down
    [ canceller, signaller ].each(&:join)

    expect(described_class.where(raised_by_id: car.id).order(:id).pluck(:status, :signals))
      .to eq([ [ "cancelled", 1 ], [ "pending", 1 ] ])
  end
end
