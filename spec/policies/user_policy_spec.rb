require "rails_helper"

RSpec.describe UserPolicy do
  subject(:policy) { described_class }

  let(:dispatcher) { build(:user) }
  let(:supervisor) { build(:user, :supervisor) }
  let(:administrator) { build(:user, :administrator) }

  permissions :index?, :show?, :new?, :create?, :edit?, :update?, :destroy? do
    it "lets only the administrator manage users", :aggregate_failures do
      expect(policy).to permit(administrator, User.new)
      expect(policy).not_to permit(supervisor, User.new)
      expect(policy).not_to permit(dispatcher, User.new)
    end
  end
end
