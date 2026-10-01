require "rails_helper"

RSpec.describe CallPolicy do
  subject(:policy) { described_class }

  permissions :new?, :create?, :edit?, :update? do
    it "lets every role register and edit calls, and nobody without a sign-in (BR-14)", :aggregate_failures do
      [ build(:user), build(:user, :supervisor), build(:user, :administrator) ].each do |user|
        expect(policy).to permit(user, AlarmCall.new)
      end
      expect(policy).not_to permit(nil, AlarmCall.new)
    end
  end
end
