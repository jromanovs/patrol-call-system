require "rails_helper"

RSpec.describe StatisticsPolicy do
  subject(:policy) { described_class }

  permissions :show? do
    it "lets every role see the statistics, and nobody without a sign-in (BR-14)", :aggregate_failures do
      [ build(:user), build(:user, :supervisor), build(:user, :administrator) ].each do |user|
        expect(policy).to permit(user, :statistics)
      end
      expect(policy).not_to permit(nil, :statistics)
    end
  end
end
