require "rails_helper"

RSpec.describe "Deleting one call" do
  include_context "without the seeded records"

  let(:car) { create(:patrol_car) }

  def call_in(status)
    create(:alarm_call).tap { |call| call.update_columns(status: Call.statuses.fetch(status), patrol_car_id: car.id) }
  end

  def delete_button(call)
    get call_path(call)
    response.parsed_body.at_css(".page-heading form[action='#{call_path(call)}'] button")
  end

  context "when signed in as a supervisor" do
    before { sign_in_as(create(:user, :supervisor)) }

    %w[ closed cancelled ].each do |status|
      it "deletes a #{status} call after the confirmation; its site and car remain (DEL-05)", :aggregate_failures do
        call = call_in(status)
        expect(delete_button(call).ancestors("form").first["data-turbo-confirm"]).to be_present

        delete call_path(call)

        expect(response).to redirect_to(calls_path)
        expect(flash[:notice]).to eq("Call deleted")
        expect(Call.exists?(call.id)).to be(false)
        expect([ GuardedSite.exists?(call.guarded_site_id), PatrolCar.exists?(car.id) ]).to eq([ true, true ])
      end
    end

    Call::ACTIVE.each do |status|
      it "refuses a #{status} call and offers no Delete on its page (DEL-06, BR-8)", :aggregate_failures do
        call = call_in(status)
        expect(delete_button(call)).to be_nil

        delete call_path(call)

        expect(response).to redirect_to(call_path(call))
        expect(flash[:alert]).to eq("Active call cannot be deleted; cancel or close it first")
        expect(Call.exists?(call.id)).to be(true)
      end
    end
  end

  context "when signed in as a dispatcher" do
    before { sign_in_as(create(:user)) }

    it "offers no Delete and refuses the request (BR-14, AUTH-07)", :aggregate_failures do
      call = call_in("closed")
      expect(delete_button(call)).to be_nil

      delete call_path(call)

      expect(flash[:alert]).to eq("Not allowed for your role")
      expect(Call.exists?(call.id)).to be(true)
    end
  end
end
