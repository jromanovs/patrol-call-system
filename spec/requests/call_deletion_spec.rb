require "rails_helper"

RSpec.describe "Deleting one call" do
  include_context "without the seeded records"

  let(:car) { create(:patrol_car) }
  let(:closed) do
    create(:alarm_call).tap { |call| call.update_columns(status: Call.statuses[:closed], patrol_car_id: car.id) }
  end
  let(:pending) { create(:alarm_call) }

  def delete_button(call)
    get call_path(call)
    response.parsed_body.at_css(".page-heading form[action='#{call_path(call)}'] button")
  end

  context "when signed in as a supervisor" do
    before { sign_in_as(create(:user, :supervisor)) }

    it "deletes a finished call after the confirmation; its site and car remain (DEL-05)", :aggregate_failures do
      site = closed.guarded_site
      expect(delete_button(closed).ancestors("form").first["data-turbo-confirm"]).to be_present

      delete call_path(closed)

      expect(response).to redirect_to(calls_path)
      expect(flash[:notice]).to eq("Call deleted")
      expect(Call.exists?(closed.id)).to be(false)
      expect([ GuardedSite.exists?(site.id), PatrolCar.exists?(car.id) ]).to eq([ true, true ])
    end

    it "refuses an active call and offers no Delete on its page (DEL-06, BR-8)", :aggregate_failures do
      expect(delete_button(pending)).to be_nil

      delete call_path(pending)

      expect(response).to redirect_to(call_path(pending))
      expect(flash[:alert]).to eq("Active call cannot be deleted; cancel or close it first")
      expect(Call.exists?(pending.id)).to be(true)
    end
  end

  context "when signed in as a dispatcher" do
    before { sign_in_as(create(:user)) }

    it "offers no Delete and refuses the request (BR-14, AUTH-07)", :aggregate_failures do
      expect(delete_button(closed)).to be_nil

      delete call_path(closed)

      expect(flash[:alert]).to eq("Not allowed for your role")
      expect(Call.exists?(closed.id)).to be(true)
    end
  end
end
