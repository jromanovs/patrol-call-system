# The test database made by db:prepare (as in CI) holds the seeds; specs of
# the address register count from an empty address table. The transaction of
# every example rolls this back.
RSpec.shared_context "with an empty address table" do
  before do
    GuardedSite.delete_all
    Address.delete_all
  end
end
