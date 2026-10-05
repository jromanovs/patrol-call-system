require "rails_helper"

RSpec.describe "The user's own profile (USR-05, USR-06)" do
  let(:password) { "correct-horse-battery" }
  let(:user) { create(:user, name: "Demo Dispatcher", email_address: "dispatcher@example.com", password:) }

  def page = response.parsed_body

  def send_change(current: password, new: "another-long-password", again: new)
    patch password_path, params: { user: { password_challenge: current, password: new, password_confirmation: again } }
  end

  context "when signed in as a dispatcher" do
    before { sign_in_as(user) }

    it "opens from the first item of the account menu, marked there as the current page", :aggregate_failures do
      get profile_path

      expect(response).to have_http_status(:ok)
      expect(page.at_css("main h1").text).to eq("Profile")
      first = page.at_css("#account-menu a")
      expect([ first.text.strip, first[:href], first["aria-current"] ]).to eq([ "Profile", profile_path, "page" ])
    end

    it "shows the initials, the name, the address and the role, and says who changes them", :aggregate_failures do
      get profile_path

      card = page.at_css("main section[aria-label='Account']")
      expect(card.at_css("[aria-hidden='true']").text.strip).to eq("DD")
      expect(card.text.squish).to include(
        "Demo Dispatcher", "dispatcher@example.com · Dispatcher",
        "The name, the address and the role are changed on the Users page by an administrator."
      )
    end

    it "leads to the change of the password and to the API key page", :aggregate_failures do
      get profile_path

      security = page.at_css("main section[aria-labelledby=profile-security-title]")
      expect(security.at_css("h2").text).to eq("Security")
      expect(security.css("a").map { |link| [ link.text.squish, link[:href] ] })
        .to eq([ [ "Change password", edit_password_path ], [ "Open the API key page", api_key_path ] ])
      expect(security.text.squish).to include("No key issued yet")
    end

    it "says when the API key was issued" do
      travel_to(Time.zone.local(2026, 10, 2, 10, 0)) { user.issue_api_key }
      get profile_path

      expect(page.at_css("main section[aria-labelledby=profile-security-title]").text.squish).to include("Issued 02.10.2026 10:00")
    end
  end

  describe "the change of the password (USR-06)" do
    before do
      ApplicationController::ATTEMPTS.clear
      sign_in_as(user)
    end

    it "asks for the current password and for the new one twice, each field with a label and a hint", :aggregate_failures do
      get edit_password_path

      expect(page.at_css("main h1").text).to eq("Change password")
      expect(page.css("main form[action='#{password_path}'] label").map { |label| label.text.squish })
        .to eq([ "Current password", "New password", "Repeat the new password" ])
      expect(page.css("main input[type=password]").map { |field| field["autocomplete"] })
        .to eq(%w[ current-password new-password new-password ])
      expect(page.at_css("#user_password")["aria-describedby"]).to eq("user_password_hint")
      expect(page.at_css("#user_password_hint").text.squish)
        .to eq("12 to 72 characters; a letter with a mark or of another alphabet (ā, ж) counts as two or more")
      expect(fields_without_label_or_hint(page)).to be_empty
    end

    it "changes the password, keeps this session and ends the user's others", :aggregate_failures do
      mine = user.sessions.sole
      other = user.sessions.create!
      send_change

      expect(response).to have_http_status(:see_other)
      expect([ response.location, flash[:notice] ]).to eq([ profile_url, "Password changed. Other devices are signed out" ])
      expect(user.reload.authenticate("another-long-password")).to be_truthy
      expect(user.sessions.ids).to eq([ mine.id ]), "the other session #{other.id} must be gone"
      get profile_path
      expect(response).to have_http_status(:ok)
    end

    it "changes nothing but the password, whatever else is sent with it", :aggregate_failures do
      patch password_path, params: { user: { password_challenge: password, password: "another-long-password",
                                             password_confirmation: "another-long-password", role: "administrator",
                                             active: "0", email_address: "other@example.com", name: "Other Name" } }

      expect(flash[:notice]).to eq("Password changed. Other devices are signed out")
      expect(user.reload.attributes.values_at("role", "active", "email_address", "name"))
        .to eq([ "dispatcher", true, "dispatcher@example.com", "Demo Dispatcher" ])
    end

    it "takes a new password sent as a number for the characters it is written with", :aggregate_failures do
      patch password_path, as: :json,
                           params: { user: { password_challenge: password, password: 123_456_789_012, password_confirmation: 123_456_789_012 } }

      expect(response).to have_http_status(:see_other)
      expect(user.reload.authenticate("123456789012")).to be_truthy
    end

    it "refuses a request whose fields come as one value or as a list, as it refuses none sent", :aggregate_failures do
      [ "typed", [ "typed" ] ].each do |sent|
        patch password_path, params: { user: sent }

        expect(response).to have_http_status(:unprocessable_content)
        expect(page.at_css("#user_password_challenge_error").text).to eq("Current password is wrong")
      end
      expect(user.reload.authenticate(password)).to be_truthy
    end

    it "leaves the sessions of other users alone" do
      another = create(:user).sessions.create!

      expect { send_change }.not_to(change { Session.exists?(another.id) })
    end

    it "refuses a wrong current password beside its field and changes nothing", :aggregate_failures do
      other = user.sessions.create!
      send_change(current: "not-the-current-one")

      expect(response).to have_http_status(:unprocessable_content)
      field = page.at_css("input#user_password_challenge[aria-invalid=true]")
      expect(field["aria-describedby"]).to eq("user_password_challenge_hint user_password_challenge_error")
      expect(page.at_css("#user_password_challenge_error").text).to eq("Current password is wrong")
      expect(page.css(".error-summary li a").map { |link| [ link.text, link[:href] ] })
        .to eq([ [ "Current password is wrong", "#user_password_challenge" ] ])
      expect([ user.reload.authenticate(password).present?, Session.exists?(other.id) ]).to eq([ true, true ])
    end

    it "refuses the change without the current password, also when the field is not sent at all", :aggregate_failures do
      [ { password_challenge: "", password: "another-long-password", password_confirmation: "another-long-password" },
        { password: "another-long-password", password_confirmation: "another-long-password" }, {} ].each do |sent|
        patch password_path, params: { user: sent }

        expect(response).to have_http_status(:unprocessable_content)
        expect(page.at_css("#user_password_challenge_error").text).to eq("Current password is wrong")
      end
      expect(user.reload.authenticate(password)).to be_truthy
    end

    it "refuses a new password that is too short, too long or none, beside its field", :aggregate_failures do
      # 40 letters of two bytes each: the limit of 72 counts bytes.
      { "short-one" => "Password is too short (minimum is 12 characters)", ("a" * 73) => "Password is too long",
        ("ж" * 40) => "Password is too long", "" => "Password can't be blank" }.each do |typed, refusal|
        send_change(new: typed)

        expect(response).to have_http_status(:unprocessable_content)
        expect(page.at_css("input#user_password[aria-invalid=true]")).to be_present
        expect(page.at_css("#user_password_error").text).to eq(refusal)
      end
      expect(user.reload.authenticate(password)).to be_truthy
    end

    it "refuses two new passwords that differ, also when the second is not sent", :aggregate_failures do
      send_change(again: "another-long-passwerd")
      expect(response).to have_http_status(:unprocessable_content)
      expect(page.at_css("#user_password_confirmation_error").text).to eq("The two new passwords differ")

      patch password_path, params: { user: { password_challenge: password, password: "another-long-password" } }
      expect(page.at_css("#user_password_confirmation_error").text).to eq("The two new passwords differ")
      expect(user.reload.authenticate(password)).to be_truthy
    end

    it "shows no password it was sent again" do
      send_change(current: "not-the-current-one")

      expect(page.css("main input[type=password]").map { |field| field["value"] }.compact).to be_empty
    end

    it "takes 10 attempts within 3 minutes and refuses the 11th", :aggregate_failures do
      10.times { send_change(current: "not-the-current-one") }
      expect(response).to have_http_status(:unprocessable_content)

      send_change
      expect(response).to redirect_to(edit_password_path)
      expect(flash[:alert]).to eq("Try again later.")
      expect(user.reload.authenticate(password)).to be_truthy
    end

    it "counts the attempts of each user apart" do
      10.times { send_change(current: "not-the-current-one") }
      sign_in_as(create(:user, password:))
      send_change

      expect(flash[:notice]).to eq("Password changed. Other devices are signed out")
    end
  end

  it "is not for a visitor without a sign-in", :aggregate_failures do
    [ -> { get profile_path }, -> { get edit_password_path }, -> { send_change } ].each do |request|
      request.call

      expect(response).to redirect_to(new_session_path)
    end
    expect(user.reload.authenticate(password)).to be_truthy
  end

  context "when signed in as a crew" do
    let(:crew) { create(:user, :crew, password:) }

    before { sign_in_as(crew) }

    it "has the profile, without a change of the password and without the API key", :aggregate_failures do
      get profile_path

      expect(response).to have_http_status(:ok)
      expect(page.at_css("main section[aria-label='Account']").text.squish).to include("DC", "Demo Crew", "· Crew")
      security = page.at_css("main section[aria-labelledby=profile-security-title]")
      expect(security.css("a")).to be_empty
      expect(security.text.squish).to eq("Security Password The password of a crew is changed by an administrator.")
      expect(page.css("#account-menu a").map { |link| [ link.text.strip, link[:href] ] }).to eq([ [ "Profile", profile_path ] ])
    end

    it "cannot open or send the change of the password", :aggregate_failures do
      get edit_password_path
      expect(response).to redirect_to(crew_path)

      send_change
      expect(response).to redirect_to(crew_path)
      expect(flash[:alert]).to eq("Not allowed for your role")
      expect(crew.reload.authenticate(password)).to be_truthy
    end
  end
end
