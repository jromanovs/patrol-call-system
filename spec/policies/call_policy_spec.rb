require "rails_helper"

RSpec.describe CallPolicy do
  subject(:policy) { described_class }

  permissions :index?, :show?, :new?, :create?, :edit?, :update? do
    it "lets every role see, register and edit calls, and nobody without a sign-in (BR-14)", :aggregate_failures do
      [ build(:user), build(:user, :supervisor), build(:user, :administrator) ].each do |user|
        expect(policy).to permit(user, AlarmCall.new)
      end
      expect(policy).not_to permit(nil, AlarmCall.new)
    end
  end

  permissions :destroy? do
    it "lets the supervisor and the administrator delete calls, not the dispatcher (BR-14)", :aggregate_failures do
      expect(policy).to permit(build(:user, :supervisor), AlarmCall.new)
      expect(policy).to permit(build(:user, :administrator), AlarmCall.new)
      expect(policy).not_to permit(build(:user), AlarmCall.new)
      expect(policy).not_to permit(nil, AlarmCall.new)
    end
  end
end
