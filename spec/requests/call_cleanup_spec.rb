require "rails_helper"

RSpec.describe "Deleting calls by criteria" do
  include_context "without the seeded records"

  let(:criteria) { { before: "2026-09-01", statuses: %w[ closed cancelled ] } }
  let!(:active) { create(:alarm_call, received_at: Time.zone.local(2026, 8, 31, 12, 0)) }

  # Two years after the calls of these examples: by then the period they are
  # kept for has passed, and 15.09.2026 is the first day still kept.
  before do
    travel_to(Time.zone.local(2028, 9, 15, 12, 0))
    %i[ closed cancelled ].each do |status|
      create(:alarm_call, received_at: Time.zone.local(2026, 8, 31, 12, 0)).update_column(:status, Call.statuses[status])
    end
  end

  def preview(**params)
    get new_call_cleanup_path, params: params
    response.parsed_body.at_css("#cleanup-preview")
  end

  # The fingerprint of the matching calls that the preview hands on.
  def previewed(**params) = preview(**params).at_css("input[name=match]")["value"]

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
      expect(form["data-turbo-frame"]).to eq("_top")
      expect(form.at_css("button").text).to eq("Delete 2 calls")
    end

    it "hands every criterion on to the confirmation (DEL-07)" do
      Call.where(status: :closed).update_all(outcome: Call.outcomes[:other])
      form = preview(**criteria, kind: "alarm", outcome: "other", before: "2026-09-02").at_css("form")

      expect(form.css("input[type=hidden]").to_h { |field| [ field["name"], field["value"] ] })
        .to include("before" => "2026-09-02", "kind" => "alarm", "outcome" => "other")
      expect(form.css("input[name='statuses[]']").map { |field| field["value"] }).to eq(%w[ closed cancelled ])
    end

    it "deletes exactly the previewed calls and leaves the active one (DEL-07, BR-8)", :aggregate_failures do
      post call_cleanup_path, params: { **criteria, match: previewed(**criteria) }

      expect(response).to redirect_to(new_call_cleanup_path(criteria))
      expect(flash[:notice]).to eq("2 calls deleted")
      expect(Call.all).to eq([ active ])
    end

    it "deletes nothing when the match changed since the preview (DEL-07)", :aggregate_failures do
      match = previewed(**criteria)
      Call.where(status: :closed).delete_all
      active.update_column(:status, Call.statuses[:closed])
      post call_cleanup_path, params: { **criteria, match: }

      expect(flash[:alert]).to eq("The matching calls changed since the preview: 2 calls match now. Nothing was deleted")
      expect(Call.count).to eq(2)
    end

    it "deletes nothing without the match of a preview (DEL-07)", :aggregate_failures do
      post call_cleanup_path, params: criteria

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

      post call_cleanup_path, params: { before: "2026-08-01", statuses: %w[ closed ], match: CallCleanup.fingerprint([]) }
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

  describe "how long calls are kept (DEL-09, BR-23)" do
    def section = response.parsed_body.at_css("section[aria-labelledby=calls-kept-title]")

    context "when signed in as a supervisor" do
      before { sign_in_as(create(:user, :supervisor)) }

      it "tells the period and the first day still kept, without a field", :aggregate_failures do
        get new_call_cleanup_path

        expect(section.at_css("h2").text).to eq("How long calls are kept")
        expect(section.text.squish).to include(
          "Calls are kept for 24 months: a call received on 15.09.2026 or later cannot be deleted.",
          "The period is set by the administrator."
        )
        expect(section.at_css("form")).to be_nil
      end

      it "names the latest day in the hint and leaves a later one to the page's own refusal", :aggregate_failures do
        get new_call_cleanup_path
        page = response.parsed_body

        expect(page.at_css("#before-hint").text.squish)
          .to eq("Calls received before 00:00 Riga time of this day; 15.09.2026 or earlier")
        expect(page.at_css("input#before")["max"]).to be_nil
      end

      it "deletes nothing when the period grew between the preview and the confirmation", :aggregate_failures do
        Setting.current.update!(call_months: 3)
        match = previewed(before: "2027-06-01", statuses: %w[ closed cancelled ])
        Setting.current.update!(call_months: 24)

        post call_cleanup_path, params: { before: "2027-06-01", statuses: %w[ closed cancelled ], match: }
        expect(flash[:alert]).to eq("Calls received from 15.09.2026 on are kept; choose 15.09.2026 or an earlier day")
        expect(Call.count).to eq(3)
      end

      it "refuses a later day: nothing is counted and nothing is deleted", :aggregate_failures do
        frame = preview(before: "2026-09-16", statuses: %w[ closed cancelled ])
        refusal = "Calls received from 15.09.2026 on are kept; choose 15.09.2026 or an earlier day"

        expect(frame.at_css(".field-error").text).to eq(refusal)
        expect(frame.at_css("form")).to be_nil
        post call_cleanup_path, params: { before: "2026-09-16", statuses: %w[ closed cancelled ], match: "any" }
        expect(flash[:alert]).to eq(refusal)
        expect(Call.count).to eq(3)
      end

      it "takes the first day still kept itself: the calls before it have passed the period" do
        expect(preview(before: "2026-09-15", statuses: %w[ closed cancelled ]).at_css(".count").text).to eq("2 calls match")
      end

      it "cannot set the period", :aggregate_failures do
        patch call_retention_path, params: { months: "36" }

        expect(flash[:alert]).to eq("Not allowed for your role")
        expect(Setting.current.call_months).to eq(24)
      end
    end

    it "is not set by a dispatcher, a crew or a visitor without a sign-in", :aggregate_failures do
      [ create(:user), create(:user, :crew), nil ].each do |user|
        user ? sign_in_as(user) : delete(session_path)
        patch call_retention_path, params: { months: "36" }

        expect(Setting.current.call_months).to eq(24), (user&.role || "signed out")
      end
    end

    context "when signed in as the administrator" do
      before { sign_in_as(create(:user, :administrator)) }

      it "offers the period in months with its rule", :aggregate_failures do
        get new_call_cleanup_path

        expect(section.at_css("label[for=months]").text.squish).to eq("Keep calls for")
        expect(section.at_css("input#months[type=number][min='3']")["value"]).to eq("24")
        expect(section.at_css("#months-hint").text.squish).to eq(
          "Not less than 3 months. Nothing is deleted by itself: the period only allows a deletion by hand, " \
          "here or on a call's page."
        )
        expect(section.text.squish).not_to include("The period is set by the administrator.")
        expect(fields_without_label_or_hint(response.parsed_body)).to be_empty
      end

      it "saves a period and says so; a shorter one asks nothing and deletes nothing", :aggregate_failures do
        patch call_retention_path, params: { months: "36" }
        expect(response).to have_http_status(:see_other)
        expect([ response.location, flash[:notice] ]).to eq([ new_call_cleanup_url, "Calls are kept for 36 months" ])

        expect { patch call_retention_path, params: { months: "12" } }.not_to change(Call, :count)
        expect(flash[:notice]).to eq("Calls are kept for 12 months")
        expect(Setting.current.call_months).to eq(12)
      end

      it "refuses a period below 3 months or beyond 1200, or none", :aggregate_failures do
        { "2" => "least 3", "1201" => "most 1200", "" => "least 3" }.each do |months, bound|
          patch call_retention_path, params: { months: }

          expect(response).to redirect_to(new_call_cleanup_path)
          expect(flash[:alert]).to eq("Keep calls for at #{bound} months")
        end
        expect(Setting.current.call_months).to eq(24)
      end
    end
  end

  context "when signed in as a dispatcher" do
    before { sign_in_as(create(:user)) }

    it "has no link, no page and no deletion (BR-14, AUTH-07)", :aggregate_failures do
      get calls_path
      expect(response.parsed_body.at_css("a[href='#{new_call_cleanup_path}']")).to be_nil

      get new_call_cleanup_path
      expect(flash[:alert]).to eq("Not allowed for your role")

      post call_cleanup_path, params: { **criteria, match: CallCleanup.fingerprint(CallCleanup.new(criteria).ids) }
      expect(flash[:alert]).to eq("Not allowed for your role")
      expect(Call.count).to eq(3)
    end
  end
end
