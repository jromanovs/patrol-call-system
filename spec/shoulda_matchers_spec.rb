require "rails_helper"

RSpec.describe "Shoulda matchers", type: :model do
  subject(:record) { probe.new }

  let(:probe) do
    Class.new do
      include ActiveModel::Model

      attr_accessor :name

      validates :name, presence: true

      def self.name = "Probe"
    end
  end

  it { is_expected.to validate_presence_of(:name) }
end
