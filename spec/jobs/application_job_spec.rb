require "rails_helper"

RSpec.describe ApplicationJob do
  # USR-10: Rails hands a job the language of the request that queued it. A
  # job words a text for its reader, who is someone else.
  it "begins in English, whatever the language of the request that queued it" do
    job = stub_const("LanguageJob", Class.new(described_class) do
      cattr_accessor :language

      def perform = self.class.language = I18n.locale
    end)

    queued = I18n.with_locale(:ru) { job.new.serialize }
    ActiveJob::Base.execute(queued)

    expect([ queued["locale"], job.language ]).to eq([ "ru", :en ])
  end
end
