require "rails_helper"

RSpec.describe "A user's password set by the administrator (USR-08)" do
  let(:administrator) { create(:user, :administrator) }
  let(:user) { create(:user, name: "Demo Dispatcher") }

  def page = response.parsed_body

  def set(new: "another-long-password", again: new, target: user, **options)
    patch user_password_path(target), params: { user: { password: new, password_confirmation: again } }, **options
  end

  # What a refusal puts back into the open dialog.
  def answer
    stream = Nokogiri::HTML5.fragment(response.body).at_css("turbo-stream[action=replace][target=modal] template")
    Nokogiri::HTML5.fragment(stream.inner_html)
  end

  context "when signed in as the administrator" do
    before { sign_in_as(administrator) }

    it "is reached from a card beside the form of the user, which opens the dialog", :aggregate_failures do
      get edit_user_path(user)

      card = page.at_css("main section[aria-labelledby=user-password-title]")
      expect(card.at_css("h2").text).to eq("Password")
      link = card.at_css("a[href='#{edit_user_password_path(user)}']")
      expect([ link.text.strip, link["data-turbo-frame"] ]).to eq([ "Set a new password", "modal" ])
    end

    it "warns in the dialog what saving does, and asks for the new password twice", :aggregate_failures do
      get edit_user_password_path(user)
      dialog = page.at_css("turbo-frame#modal dialog")

      expect(dialog.at_css("#dialog-title").text).to eq("New password for Demo Dispatcher")
      expect(dialog.at_css(".caution").text.squish)
        .to eq("Saving signs Demo Dispatcher out on every device. The former password stops working at once.")
      form = dialog.at_css("form[action='#{user_password_path(user)}'][data-turbo-frame='_top']")
      expect(form.css("label").map { |label| label.text.squish }).to eq([ "New password", "Repeat the new password" ])
      expect(form.css("input[type=password]").map { |field| field["autocomplete"] }).to eq(%w[ new-password new-password ])
      expect(form.at_css("input[type=submit]")["value"]).to eq("Set the password")
    end

    it "gives the two fields a label and a hint, and lets Cancel close the dialog", :aggregate_failures do
      get edit_user_password_path(user)

      expect(fields_without_label_or_hint(page)).to be_empty
      cancel = page.at_css("dialog form button[type=button]")
      expect([ cancel.text.strip, cancel["data-action"] ]).to eq([ "Cancel", "dialog#close" ])
    end

    it "names the notices of a crew's phones in the warning" do
      get edit_user_password_path(create(:user, :crew))

      expect(page.at_css("dialog .caution").text.squish).to eq(
        "Saving signs Demo Crew out on every device and stops the notices on its phones until it signs in again " \
        "and turns them on. The former password stops working at once."
      )
    end

    it "names the API key in the warning of a user who has one, a crew included", :aggregate_failures do
      user.issue_api_key
      get edit_user_password_path(user)
      expect(page.at_css("dialog .caution").text.squish)
        .to eq("Saving signs Demo Dispatcher out on every device. The former password and the API key stop working at once.")

      crew = create(:user, :crew)
      crew.issue_api_key
      get edit_user_password_path(crew)
      expect(page.at_css("dialog .caution").text.squish).to end_with(
        "until it signs in again and turns them on. The former password and the API key stop working at once."
      )
    end

    it "says on the card who else changes the password: the user on the profile, a crew nobody", :aggregate_failures do
      get edit_user_path(user)
      expect(page.at_css("main section[aria-labelledby=user-password-title] p").text.squish)
        .to eq("Set by an administrator here; the user changes their own on their profile.")

      get edit_user_path(create(:user, :crew))
      expect(page.at_css("main section[aria-labelledby=user-password-title] p").text.squish)
        .to eq("Set by an administrator here only: a crew does not change its own.")
    end

    it "sets the password, signs the user out everywhere and tells so on the user's page", :aggregate_failures do
      2.times { user.sessions.create! }
      set

      expect(response).to have_http_status(:see_other)
      expect([ response.location, flash[:notice] ])
        .to eq([ edit_user_url(user), "Password of Demo Dispatcher changed; the user is signed out on every device" ])
      expect(user.reload.authenticate("another-long-password")).to be_truthy
      expect(user.sessions.count).to eq(0)
      get users_path
      expect(response).to have_http_status(:ok)
    end

    it "voids the API key of the user with the password, and tells so (BR-13)", :aggregate_failures do
      key = user.issue_api_key
      set

      expect(flash[:notice])
        .to eq("Password of Demo Dispatcher changed; the user is signed out on every device, and the API key is void")
      get api_v1_sites_path, headers: { "Authorization" => "Bearer #{key}" }
      expect(response).to have_http_status(:unauthorized)
    end

    it "leaves the API key when the password is refused" do
      key = user.issue_api_key
      set(new: "short-one", as: :turbo_stream)

      expect(User.find_by_api_key(key)).to eq(user)
    end

    it "takes the notices of a crew's phones away with its sessions" do
      crew = create(:user, :crew)
      create(:push_subscription, session: crew.sessions.create!)

      expect { set(target: crew) }.to change(PushSubscription, :count).from(1).to(0)
    end

    it "puts a refusal back into the open dialog, beside its field, and changes nothing", :aggregate_failures do
      user.sessions.create!
      { %w[ short-one short-one ] => [ "#user_password_error", "Password is too short (minimum is 12 characters)" ],
        [ "a" * 73, "a" * 73 ] => [ "#user_password_error", "Password is too long" ],
        [ "", "" ] => [ "#user_password_error", "Password can't be blank" ],
        %w[ another-long-password another-long-passwerd ] => [ "#user_password_confirmation_error", "The two new passwords differ" ] }
        .each do |(new, again), (place, refusal)|
        set(new:, again:, as: :turbo_stream)

        expect(response).to have_http_status(:unprocessable_content)
        expect(answer.at_css("dialog #{place}").text).to eq(refusal)
      end
      expect([ user.reload.authenticate("correct-horse-battery").present?, user.sessions.count ]).to eq([ true, 1 ])
    end

    it "marks the refused field and shows no typed password again", :aggregate_failures do
      set(new: "short-one", as: :turbo_stream)

      expect(answer.at_css("input#user_password[aria-invalid=true]")["aria-describedby"]).to eq("user_password_hint user_password_error")
      expect(answer.css("input[type=password]").map { |field| field["value"] }.compact).to be_empty
    end

    it "shows the refusal in the dialog alone when it is asked for as a page", :aggregate_failures do
      set(new: "short-one")

      expect(response).to have_http_status(:unprocessable_content)
      expect(page.at_css("turbo-frame#modal dialog #user_password_error").text).to eq("Password is too short (minimum is 12 characters)")
    end

    it "refuses a repeat not sent at all, and a request without its fields", :aggregate_failures do
      patch user_password_path(user), params: { user: { password: "another-long-password" } }
      expect(page.at_css("#user_password_confirmation_error").text).to eq("The two new passwords differ")

      [ {}, { user: "typed" }, { user: [ "typed" ] } ].each do |sent|
        patch user_password_path(user), params: sent

        expect(response).to have_http_status(:unprocessable_content)
        expect(page.at_css("#user_password_error").text).to eq("Password can't be blank")
      end
      expect(user.reload.authenticate("correct-horse-battery")).to be_truthy
    end

    it "changes nothing of the user but the password, whatever else is sent", :aggregate_failures do
      patch user_password_path(user), params: { user: { password: "another-long-password", password_confirmation: "another-long-password",
                                                        role: "administrator", active: "0", name: "Other Name" } }

      expect(user.reload.attributes.values_at("role", "active", "name")).to eq([ "dispatcher", true, "Demo Dispatcher" ])
    end

    # There the current password is asked for; here it is not.
    it "sends the administrator to its own profile for its own password", :aggregate_failures do
      [ -> { get edit_user_password_path(administrator) }, -> { set(target: administrator) } ].each do |request|
        request.call

        expect([ response.location, flash[:alert] ]).to eq([ profile_url, "Change your own password on your profile" ])
      end
      expect(administrator.reload.authenticate("correct-horse-battery")).to be_truthy
    end

    it "offers no dialog on the administrator's own page, and leads to the profile", :aggregate_failures do
      get edit_user_path(administrator)
      card = page.at_css("main section[aria-labelledby=user-password-title]")

      expect(card.css("a").map { |link| [ link.text.strip, link[:href] ] }).to eq([ [ "your profile", profile_path ] ])
      expect(card.text.squish).to include("Change your own password on your profile")
    end
  end

  it "is the administrator's only", :aggregate_failures do
    [ create(:user, :supervisor), create(:user), create(:user, :crew), nil ].each do |other|
      other ? sign_in_as(other) : delete(session_path)
      get edit_user_password_path(user)
      expect(response).not_to have_http_status(:ok), (other&.role || "signed out")

      set
      expect(user.reload.authenticate("correct-horse-battery")).to be_truthy, (other&.role || "signed out")
    end
    expect(response).to redirect_to(new_session_path)
  end
end
