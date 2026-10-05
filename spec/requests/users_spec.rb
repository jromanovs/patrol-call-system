require "rails_helper"

RSpec.describe "Users" do
  let(:administrator) { create(:user, :administrator) }
  let(:valid_params) do
    { user: { email_address: "new@example.com", name: "New Dispatcher", role: "dispatcher",
              password: "correct-horse-battery" } }
  end

  context "when signed in as the administrator" do
    before { sign_in_as(administrator) }

    it "lists the users and shows Users in the account menu", :aggregate_failures do
      get users_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(administrator.email_address)
      expect(response.parsed_body.css("#account-menu a").map { |link| link.text.strip }).to include("Users")
    end

    it "creates a user who can sign in", :aggregate_failures do
      expect { post users_path, params: valid_params }.to change(User, :count).by(1)

      expect(response).to redirect_to(users_path)
      expect(User.authenticate_by(email_address: "new@example.com", password: "correct-horse-battery")).to be_present
    end

    it "creates a crew user bound to a car and lists the car with the role (USR-01)", :aggregate_failures do
      car = create(:patrol_car)
      post users_path, params: { user: valid_params[:user].merge(role: "crew", patrol_car_id: car.id) }

      expect(User.find_by(email_address: "new@example.com")).to have_attributes(role: "crew", patrol_car: car)
      get users_path
      expect(response.parsed_body.css("td[data-label='Role']").map { |cell| cell.text.squish })
        .to include("Crew · #{car.call_sign}")
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

    # The password of a user is set in a dialog of its own (USR-08): the
    # form cannot change one by accident.
    it "changes no password by the form of a user, whatever is sent with it", :aggregate_failures do
      user = create(:user)
      user.sessions.create!
      patch user_path(user), params: { user: { name: "Demo Supervisor", password: "another-long-password",
                                               password_confirmation: "another-long-password" } }

      expect(response).to redirect_to(users_path)
      expect(user.reload.name).to eq("Demo Supervisor")
      expect(user.authenticate("correct-horse-battery")).to be_truthy
      expect(user.sessions.count).to eq(1)
    end

    it "holds a password field in the form of a new user only", :aggregate_failures do
      get new_user_path
      expect(response.parsed_body.at_css("main form #user_password_hint").text.squish).to eq("12 to 72 characters")

      get edit_user_path(create(:user))
      expect(response.parsed_body.css("main form input[type=password]")).to be_empty
    end

    it "ends no session when it saves a user without a new password", :aggregate_failures do
      user = create(:user)
      user.sessions.create!

      expect { patch user_path(user), params: { user: { name: "Demo Supervisor", role: "supervisor", password: "" } } }
        .not_to change(Session, :count)
      expect(user.reload.name).to eq("Demo Supervisor")
    end

    it "turns a crew user into a dispatcher, leaving the car (USR-02)", :aggregate_failures do
      crew = create(:user, :crew)
      patch user_path(crew), params: { user: { role: "dispatcher", patrol_car_id: "", password: "" } }

      expect(response).to redirect_to(users_path)
      expect(crew.reload).to have_attributes(role: "dispatcher", patrol_car: nil)
    end

    it "deletes a user together with the user's sessions" do
      user = create(:user)
      user.sessions.create!

      expect { delete user_path(user) }.to change(User, :count).by(-1).and change(Session, :count).by(-1)
    end

    it "keeps a crew user whose phone's positions calls keep, and says why (USR-03, BR-18)", :aggregate_failures do
      arrival = create(:step_position)
      crew = arrival.user
      create(:step_position, user: crew, step: :closing, call: arrival.call)

      expect { delete user_path(crew) }.not_to change(User, :count)
      expect(response).to redirect_to(users_path)
      expect(flash[:alert])
        .to eq("User has positions or photos kept at 1 call and cannot be deleted; make the user inactive instead")
    end

    it "keeps a crew user whose photos calls keep, and says why (USR-03, BR-19)", :aggregate_failures do
      crew = create(:call_photo).user

      expect { delete user_path(crew) }.not_to change(User, :count)
      expect(flash[:alert])
        .to eq("User has positions or photos kept at 1 call and cannot be deleted; make the user inactive instead")
    end

    describe "a user whose work calls keep (USR-03, BR-17)" do
      let(:worker) { create(:user) }
      let(:refusal) { "User has 1 call and cannot be deleted; make the user inactive instead" }
      let(:dispatched) do
        create(:alarm_call).tap { |call| CallStep.new(call, create(:user)).dispatch(create(:patrol_car)) }
      end

      it "keeps a user who registered a call, and says why", :aggregate_failures do
        create(:alarm_call, registered_by: worker)

        expect { delete user_path(worker) }.not_to change(User, :count)
        expect(response).to redirect_to(users_path)
        expect(flash[:alert]).to eq(refusal)
      end

      it "keeps a user who dispatched a call", :aggregate_failures do
        CallStep.new(create(:alarm_call), worker).dispatch(create(:patrol_car))

        expect { delete user_path(worker) }.not_to change(User, :count)
        expect(flash[:alert]).to eq(refusal)
      end

      it "keeps a user who acknowledged a crew's SOS", :aggregate_failures do
        create(:sos_call).acknowledge(worker)

        expect { delete user_path(worker) }.not_to change(User, :count)
        expect(flash[:alert]).to eq(refusal)
      end

      it "keeps a user who sent a further car", :aggregate_failures do
        BackupStep.new(dispatched, worker).send_car(create(:patrol_car))

        expect { delete user_path(worker) }.not_to change(User, :count)
        expect(flash[:alert]).to eq(refusal)
      end

      it "keeps a crew user whose SOS from the crew screen became a call", :aggregate_failures do
        crew = create(:user, :crew)
        SosCall.signal(crew.patrol_car, {}, by: crew)

        expect { delete user_path(crew) }.not_to change(User, :count)
        expect(flash[:alert]).to eq(refusal)
      end

      it "counts a call once, whatever ties the user to it", :aggregate_failures do
        call = create(:alarm_call, registered_by: worker)
        CallStep.new(call, worker).dispatch(create(:patrol_car))
        create(:client_call, registered_by: worker)
        create(:alarm_call)

        expect { delete user_path(worker) }.not_to change(User, :count)
        expect(flash[:alert]).to eq("User has 2 calls and cannot be deleted; make the user inactive instead")
      end

      it "counts a call once when the user dispatched it and sent further cars to it", :aggregate_failures do
        call = create(:alarm_call).tap { |one| CallStep.new(one, worker).dispatch(create(:patrol_car)) }
        2.times { BackupStep.new(call, worker).send_car(create(:patrol_car)) }

        expect { delete user_path(worker) }.not_to change(User, :count)
        expect(flash[:alert]).to eq(refusal)
      end

      it "counts a call once when it also keeps the user's position and photos", :aggregate_failures do
        call = create(:alarm_call, registered_by: worker)
        create(:step_position, call:, user: worker)
        create_list(:call_photo, 2, call:, user: worker)

        expect { delete user_path(worker) }.not_to change(User, :count)
        expect(flash[:alert]).to eq(refusal)
      end

      it "deletes the user once the call that kept the user is deleted" do
        call = create(:alarm_call, registered_by: worker, received_at: 25.months.ago)
        CallStep.new(call, worker).cancel("Entered by mistake")
        call.destroy!

        expect { delete user_path(worker) }.to change(User, :count).by(-1)
      end

      it "counts the calls that keep a crew user's positions with the calls of its own", :aggregate_failures do
        crew = create(:step_position).user
        SosCall.signal(crew.patrol_car, {}, by: crew)

        expect { delete user_path(crew) }.not_to change(User, :count)
        expect(flash[:alert]).to eq("User has 2 calls and cannot be deleted; make the user inactive instead")
      end

      it "deletes nothing of a user it keeps: the calls and the user's sessions stay", :aggregate_failures do
        create(:alarm_call, registered_by: worker)
        worker.sessions.create!

        expect { delete user_path(worker) }.not_to(change { [ Call.count, Session.count ] })
        expect(worker.reload).to be_active
      end
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
