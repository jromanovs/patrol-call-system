# The test database made by db:prepare (as in CI) holds the seeds; specs that
# count records start without them. The transaction of every example rolls
# this back.
RSpec.shared_context "without the seeded records" do
  before do
    Call.delete_all
    PatrolCar.delete_all
    GuardedSite.delete_all
    Address.delete_all
  end
end
