require "rails_helper"

RSpec.describe ApplicationCable::Connection do
  let(:user) { create(:user) }

  it "connects a signed-in user" do
    cookies.signed[:session_id] = user.sessions.create!.id
    connect "/cable"

    expect(connection.current_user).to eq(user)
  end

  it "refuses a visitor without a session" do
    expect { connect "/cable" }.to have_rejected_connection
  end

  it "refuses the session of a user made inactive (BR-13)" do
    cookies.signed[:session_id] = user.sessions.create!.id
    user.update_column(:active, false)

    expect { connect "/cable" }.to have_rejected_connection
  end
end
