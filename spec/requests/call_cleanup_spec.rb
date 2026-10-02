require "rails_helper"

RSpec.describe "Deleting calls by criteria" do
  include_context "without the seeded records"

  let(:criteria) { { before: "2026-09-01", statuses: %w[ closed cancelled ] } }
  let!(:active) { create(:alarm_call, received_at: Time.zone.local(2026, 8, 31, 12, 0)) }

  before do
    %i[ closed cancelled ].each do |status|
      create(:alarm_call, received_at: Time.zone.local(2026, 8, 31, 12, 0)).update_column(:status, Call.statuses[status])
    end
  end

  def preview(**params)
    get new_call_cleanup_path, params: params
    response.parsed_body.at_css("#cleanup-preview")
  end

  context "when signed in as a supervisor" do
    before { sign_in_as(create(:user, :supervisor)) }

    it "is linked from the call list" do
      get calls_path

      expect(response.parsed_body.at_css(".page-heading a[href='#{new_call_cleanup_path}']").text).to eq("Delete old calls")
    end

    it "previews the number of matching calls and asks to confirm the deletion (DEL-07)", :aggregate_failures do
      frame = preview(**criteria)

      expect(frame.at_css(".count").text).to eq("2 calls match")
      form = frame.at_css("form[action='#{call_cleanup_path}']")
      expect(form["data-turbo-confirm"]).to eq("Delete 2 calls? This cannot be undone.")
      expect(form.at_css("input[name=count]")["value"]).to eq("2")
      expect(form.at_css("button").text).to eq("Delete 2 calls")
    end

    it "deletes exactly the previewed calls and leaves the active one (DEL-07, BR-8)", :aggregate_failures do
      post call_cleanup_path, params: { **criteria, count: 2 }

      expect(response).to redirect_to(new_call_cleanup_path(criteria))
      expect(flash[:notice]).to eq("2 calls deleted")
      expect(Call.all).to eq([ active ])
    end

    it "deletes nothing when the match changed since the preview (DEL-07)", :aggregate_failures do
      post call_cleanup_path, params: { **criteria, count: 1 }

      expect(flash[:alert]).to eq("The matching calls changed since the preview: 2 calls match now. Nothing was deleted")
      expect(Call.count).to eq(3)
    end

    it "names a future day and a missing status (DEL-08)", :aggregate_failures do
      tomorrow = Time.zone.tomorrow.iso8601

      expect(preview(before: tomorrow, statuses: %w[ closed ]).at_css(".field-error").text)
        .to eq("Received before cannot be in the future")
      expect(preview(before: "2026-09-01").at_css(".field-error").text).to eq("Choose closed, cancelled or both")
    end

    it "deletes nothing when nothing matches (DEL-08)", :aggregate_failures do
      frame = preview(before: "2026-08-01", statuses: %w[ closed ])
      expect(frame.at_css(".count").text).to eq("No calls match")
      expect(frame.at_css("form")).to be_nil

      post call_cleanup_path, params: { before: "2026-08-01", statuses: %w[ closed ], count: 0 }
      expect(flash[:alert]).to eq("No calls match")
      expect(Call.count).to eq(3)
    end

    it "recounts the match in place on every change (DYN-08)", :aggregate_failures do
      get new_call_cleanup_path
      form = response.parsed_body.at_css("form.filters")
      expect(form["data-turbo-frame"]).to eq("cleanup-preview")
      expect(form.css("input[type=date], input[type=checkbox], select").map { |field| field["data-action"] })
        .to all(eq("change->auto-submit#submit"))
      expect(response.parsed_body.at_css("turbo-frame#cleanup-preview[data-turbo-action=advance]")).to be_present

      get new_call_cleanup_path, params: criteria, headers: { "Turbo-Frame" => "cleanup-preview" }
      expect(response.parsed_body.at_css("header.site-header")).to be_nil
    end

    it "gives every field a label and a hint (DSP-04)" do
      get new_call_cleanup_path

      expect(fields_without_label_or_hint(response.parsed_body)).to be_empty
    end
  end

  context "when signed in as a dispatcher" do
    before { sign_in_as(create(:user)) }

    it "has no link, no page and no deletion (BR-14, AUTH-07)", :aggregate_failures do
      get calls_path
      expect(response.parsed_body.at_css("a[href='#{new_call_cleanup_path}']")).to be_nil

      get new_call_cleanup_path
      expect(flash[:alert]).to eq("Not allowed for your role")

      post call_cleanup_path, params: { **criteria, count: 2 }
      expect(flash[:alert]).to eq("Not allowed for your role")
      expect(Call.count).to eq(3)
    end
  end
end
