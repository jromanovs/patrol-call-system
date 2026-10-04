require "rails_helper"

RSpec.describe "Deleting one call" do
  include_context "without the seeded records"

  let(:car) { create(:patrol_car) }

  # Received before the period calls are kept for, unless another time is given.
  def call_in(status, received_at: 25.months.ago)
    create(:alarm_call, received_at:).tap do |call|
      call.update_columns(status: Call.statuses.fetch(status), patrol_car_id: car.id)
    end
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

    it "offers no Delete for a finished call still kept, says until when, and refuses the request (DEL-05, BR-23)",
       :aggregate_failures do
      travel_to(Time.zone.local(2026, 10, 4, 12, 0))
      call = call_in("closed", received_at: Time.zone.local(2026, 3, 14, 9, 12))

      expect(delete_button(call)).to be_nil
      expect(response.parsed_body.at_css(".page-heading .kept-until").text.squish).to eq("Kept until 14.03.2028")
      delete call_path(call)

      expect(response).to redirect_to(call_path(call))
      expect(flash[:alert]).to eq("Call is kept until 14.03.2028 and cannot be deleted")
      expect(Call.exists?(call.id)).to be(true)
    end

    it "says nothing of keeping on the page of an active call" do
      get call_path(call_in("pending", received_at: Time.current))

      expect(response.parsed_body.at_css(".kept-until")).to be_nil
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

    it "offers no Delete, says nothing of keeping, and refuses the request (BR-14, AUTH-07)", :aggregate_failures do
      call = call_in("closed", received_at: 1.month.ago)
      expect(delete_button(call)).to be_nil
      expect(response.parsed_body.at_css(".kept-until")).to be_nil

      delete call_path(call)

      expect(flash[:alert]).to eq("Not allowed for your role")
      expect(Call.exists?(call.id)).to be(true)
    end
  end
end
