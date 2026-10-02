require "rails_helper"

RSpec.describe "Users" do
  let(:administrator) { create(:user, :administrator) }
  let(:valid_params) do
    { user: { email_address: "new@example.com", name: "New Dispatcher", role: "dispatcher",
              password: "correct-horse-battery" } }
  end

  context "when signed in as the administrator" do
    before { sign_in_as(administrator) }

    it "lists the users and shows Users in the menu", :aggregate_failures do
      get users_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(administrator.email_address)
      expect(response.parsed_body.css("nav[aria-label='Main'] a").map(&:text)).to include("Users")
    end

    it "creates a user who can sign in", :aggregate_failures do
      expect { post users_path, params: valid_params }.to change(User, :count).by(1)

      expect(response).to redirect_to(users_path)
      expect(User.authenticate_by(email_address: "new@example.com", password: "correct-horse-battery")).to be_present
    end

    it "creates a crew user bound to a car and lists the car with the role (USR-01)", :aggregate_failures do
      car = create(:patrol_car, call_sign: "P-12")
      post users_path, params: { user: valid_params[:user].merge(role: "crew", patrol_car_id: car.id) }

      expect(User.find_by(email_address: "new@example.com")).to have_attributes(role: "crew", patrol_car: car)
      get users_path
      expect(response.parsed_body.css("td[data-label='Role']").map { |cell| cell.text.squish }).to include("Crew · P-12")
    end

    it "refuses a crew user without a car, with the reason at the field (USR-01)", :aggregate_failures do
      post users_path, params: { user: valid_params[:user].merge(role: "crew") }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.at_css("#user_patrol_car_id_error").text).to include("must be chosen for a crew")
    end

    it "shows the form again with the errors for invalid data" do
      post users_path, params: { user: valid_params[:user].merge(email_address: "not-an-address") }

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "lists the errors first, each linked to its field, and repeats each above the field", :aggregate_failures do
      post users_path, params: { user: valid_params[:user].merge(email_address: "not-an-address") }

      page = response.parsed_body
      expect(page.css(".error-summary a").map { |link| link["href"] }).to eq([ "#user_email_address" ])
      field = page.at_css("#user_email_address")
      expect(field["aria-describedby"].split).to include("user_email_address_error")
      expect(page.at_css(".field-error#user_email_address_error").text).to eq("Email address is invalid")
    end

    it "gives every field of the user form a label and a hint", :aggregate_failures do
      get new_user_path
      expect(fields_without_label_or_hint(response.parsed_body)).to be_empty

      get edit_user_path(create(:user))
      expect(fields_without_label_or_hint(response.parsed_body)).to be_empty
    end

    it "shows the last sign-in in Riga time as DD.MM.YYYY HH:MM, summer and winter" do
      create(:user, last_signed_in_at: Time.utc(2026, 10, 1, 14, 12))
      create(:user, last_signed_in_at: Time.utc(2026, 1, 15, 10, 0))
      get users_path

      cells = response.parsed_body.css("td[data-label='Last sign-in']").map { |cell| cell.text.strip }
      expect(cells).to contain_exactly("01.10.2026 17:12", "15.01.2026 12:00", "—")
    end

    it "names the column in every cell, so the table reads as cards in a narrow window" do
      get users_path

      table = response.parsed_body.at_css("table.data-table")
      headers = table.css("thead th").map { |header| header.text.strip }
      expect(table.css("tbody tr").map { |row| row.css("td").map { |cell| cell["data-label"] } }).to all(eq(headers))
    end

    it "changes the role and makes a user inactive without a new password", :aggregate_failures do
      user = create(:user)
      patch user_path(user), params: { user: { role: "supervisor", active: "0", password: "" } }

      expect(response).to redirect_to(users_path)
      expect(user.reload).to have_attributes(role: "supervisor", active: false)
    end

    it "turns a crew user into a dispatcher, leaving the car (USR-02)", :aggregate_failures do
      crew = create(:user, :crew)
      patch user_path(crew), params: { user: { role: "dispatcher", patrol_car_id: "", password: "" } }

      expect(response).to redirect_to(users_path)
      expect(crew.reload).to have_attributes(role: "dispatcher", patrol_car: nil)
    end

    it "deletes a user" do
      user = create(:user)

      expect { delete user_path(user) }.to change(User, :count).by(-1)
    end
  end

  context "when signed in as a dispatcher" do
    before { sign_in_as(create(:user)) }

    it "refuses the users page with a message", :aggregate_failures do
      get users_path

      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq("Not allowed for your role")
    end
  end
end
