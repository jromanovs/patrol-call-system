require "rails_helper"

# The errors of production are seen as a list with the count of each and the
# time it last happened (solid_errors), by the administrator only (BR-14).
RSpec.describe "The page of errors" do
  include_context "without the seeded records"

  def page = response.parsed_body

  it "keeps an exception raised in a request, with its class, message and count", :aggregate_failures do
    sign_in_as(create(:user))
    allow(CallFilter).to receive(:new).and_raise(RuntimeError, "the filter failed")

    expect { get calls_path }.to raise_error(RuntimeError)
    expect { get calls_path }.to raise_error(RuntimeError)

    error = SolidErrors::Error.sole
    expect([ error.exception_class, error.message, error.occurrences.count ])
      .to eq([ "RuntimeError", "the filter failed", 2 ])
  end

  it "lists the errors to the administrator with their count", :aggregate_failures do
    Rails.error.report(RuntimeError.new("the filter failed"))
    sign_in_as(create(:user, :administrator))

    get "/errors"

    expect(response).to have_http_status(:ok)
    expect(page.text).to include("RuntimeError", "the filter failed")
  end

  it "lets the administrator open an error and mark it resolved", :aggregate_failures do
    Rails.error.report(RuntimeError.new("the filter failed"))
    error = SolidErrors::Error.sole
    sign_in_as(create(:user, :administrator))

    get "/errors/#{error.id}"
    expect(response).to have_http_status(:ok)

    patch "/errors/#{error.id}", params: { error: { resolved_at: Time.current } }
    expect([ response.location, error.reload.resolved? ]).to eq([ "http://www.example.com/errors/", true ])
  end

  it "refuses a user of another role and keeps the list closed", :aggregate_failures do
    sign_in_as(create(:user, :supervisor))

    get "/errors"

    expect(response).to redirect_to("/")
    expect(flash[:alert]).to eq("Not allowed for your role")
  end

  it "sends a crew user back to its screen" do
    sign_in_as(create(:user, :crew))

    get "/errors"

    expect(response).to redirect_to("/crew")
  end

  it "sends a visitor who is not signed in to the sign-in page" do
    get "/errors"

    expect(response).to redirect_to("/session/new")
  end

  it "removes the occurrences of a resolved error older than 30 days" do
    expect(SolidErrors.destroy_after).to eq(30.days)
  end

  it "sends no e-mail about an error" do
    expect(SolidErrors.send_emails).to be_falsey
  end
end
