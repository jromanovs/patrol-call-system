require "rails_helper"

RSpec.describe PatrolCarPolicy do
  subject(:policy) { described_class }

  permissions :index?, :show?, :new?, :create?, :edit?, :update?, :destroy? do
    it "lets every role maintain cars, and nobody without a sign-in (BR-14)", :aggregate_failures do
      [ build(:user), build(:user, :supervisor), build(:user, :administrator) ].each do |user|
        expect(policy).to permit(user, PatrolCar.new)
      end
      expect(policy).not_to permit(nil, PatrolCar.new)
    end
  end
end
