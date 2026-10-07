require "rails_helper"

RSpec.describe "Calls" do
  let(:dispatcher) { create(:user) }
  let(:site) { create(:guarded_site, name: "Warehouse No. 3", contract_number: "C-00042") }
  let(:fields) { { kind: "alarm", guarded_site_id: site.id, alarm_type: "panic", sensor_zone: "1" } }
  let(:client_fields) do
    { kind: "client", guarded_site_id: site.id, caller_name: "Example Person", caller_phone: "+37100000005",
      priority: "", description: "Check of the premises" }
  end

  before { sign_in_as(dispatcher) }

  describe "the call form" do
    it "gives every field a label and a hint (DSP-04)" do
      get new_call_path

      expect(fields_without_label_or_hint(response.parsed_body)).to be_empty
    end

    it "offers only sites with an active contract (BR-1)", :aggregate_failures do
      site
      create(:guarded_site, :suspended, name: "Closed Shop")
      get new_call_path

      options = response.parsed_body.css("#call_guarded_site_id option").map(&:text).join(" | ")
      expect(options).to include("Warehouse No. 3 · C-00042")
      expect(options).not_to include("Closed Shop")
    end

    it "follows the call type and knows the BR-2 defaults (DYN-04)", :aggregate_failures do
      get new_call_path

      form = response.parsed_body.at_css("form[data-controller~='call-form']")
      expect(JSON.parse(form["data-call-form-priorities-value"])).to eq(AlarmCall::PRIORITIES)
      expect(form.css("input[name='call[kind]']").map { |radio| radio["value"] }).to eq(%w[alarm client])
      expect(form.at_css("fieldset[data-call-form-target='client']")).to have_attributes(attributes: include("disabled", "hidden"))
      expect(form.at_css("fieldset[data-call-form-target='alarm']")["disabled"]).to be_nil
    end
  end

  describe "an alarm call" do
    it "is registered and the board opens (ADD-05)", :aggregate_failures do
      expect { post calls_path, params: { call: fields } }.to change(AlarmCall, :count).by(1)

      expect(response).to redirect_to(root_path)
      expect(flash[:notice]).to eq("Alarm call registered")
      expect(AlarmCall.last).to have_attributes(status: "pending", priority: "critical", guarded_site: site,
                                                registered_by: dispatcher)
    end

    it "refuses zones 0 and 100 with a message at the field and saves nothing (ADD-06)", :aggregate_failures do
      %w[0 100].each do |zone|
        expect { post calls_path, params: { call: fields.merge(sensor_zone: zone) } }.not_to change(Call, :count)

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body.at_css("#call_sensor_zone_error")&.text).to eq("Sensor zone must be from 1 to 99")
      end
    end

    it "refuses a time of receipt one minute ahead (ADD-06)", :aggregate_failures do
      freeze_time do
        received_at = 1.minute.from_now.strftime("%Y-%m-%dT%H:%M")
        expect { post calls_path, params: { call: fields.merge(received_at:) } }.not_to change(Call, :count)

        expect(response.parsed_body.at_css("#call_received_at_error")&.text).to eq("Time received cannot be in the future")
      end
    end
  end

  describe "a client call" do
    it "is registered with Normal priority and shows on the board (ADD-07)", :aggregate_failures do
      expect { post calls_path, params: { call: client_fields } }.to change(ClientCall, :count).by(1)
      expect(flash[:notice]).to eq("Client call registered")
      expect(ClientCall.last).to have_attributes(status: "pending", priority: "normal", caller_name: "Example Person")

      get root_path
      expect(response.parsed_body.at_css(".call-card [data-label='Call']").text.squish).to eq("Client call Example Person, +37100000005")
    end

    it "keeps the priority the dispatcher chose (ADD-07)" do
      post calls_path, params: { call: client_fields.merge(priority: "high") }

      expect(ClientCall.last.priority).to eq("high")
    end

    it "refuses a wrong phone and a short name with messages at the fields", :aggregate_failures do
      wrong = client_fields.merge(caller_phone: "12345", caller_name: "X")
      expect { post calls_path, params: { call: wrong } }.not_to change(Call, :count)

      expect(response.parsed_body.at_css("#call_caller_phone_error")).to be_present
      expect(response.parsed_body.at_css("#call_caller_name_error")).to be_present
      expect(response.parsed_body.at_css("fieldset[data-call-form-target='client']")["disabled"]).to be_nil
    end
  end

  it "refuses a site with a suspended contract with the ADD-08 message (BR-1)", :aggregate_failures do
    closed = create(:guarded_site, :suspended, contract_number: "C-00043")

    expect { post calls_path, params: { call: fields.merge(guarded_site_id: closed.id) } }.not_to change(Call, :count)
    expect(response.parsed_body.at_css(".error-summary").text).to include(
      "Contract C-00043 is suspended — call cannot be registered"
    )
  end

  describe "editing (UPD-05)" do
    let(:call) { create(:client_call, guarded_site: site) }

    it "changes priority, description and the caller of an active call", :aggregate_failures do
      patch call_path(call), params: { call: { priority: "low", description: "Keys at the neighbour", caller_name: "Other Person" } }

      expect(response).to redirect_to(root_path)
      expect(flash[:notice]).to eq("Call updated")
      expect(call.reload).to have_attributes(priority: "low", description: "Keys at the neighbour", caller_name: "Other Person")
    end

    it "gives every field of the edit form a label and a hint (DSP-04)" do
      get edit_call_path(call)

      expect(fields_without_label_or_hint(response.parsed_body)).to be_empty
    end

    it "refuses a closed call (BR-7)", :aggregate_failures do
      call.update_column(:status, Call.statuses[:closed])
      patch call_path(call), params: { call: { priority: "low" } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(call.reload.priority).to eq("normal")
    end
  end

  describe "the board" do
    it "shows a call with priority, site, alarm, status, waiting time and time received (DSP-03)", :aggregate_failures do
      travel_to Time.zone.local(2026, 10, 1, 15, 45) do
        create(:alarm_call, guarded_site: site, alarm_type: :fire, sensor_zone: 7, received_at: 13.minutes.ago)
        get root_path
      end

      card = response.parsed_body.at_css(".calls-panel article.call-card")
      cells = card.css("[data-label]").to_h { |part| [ part["data-label"], part.text.squish ] }
      expect(card["class"]).to include("critical")
      expect(cells).to include("Priority" => "Critical", "Call" => "Alarm: fire Zone 7", "Status" => "Pending",
                               "Arrival" => "Waiting for a car", "Waiting" => "13 min 01.10.2026 15:32")
      expect(cells["Site"]).to eq("Warehouse No. 3 C-00042 · Jēkaba iela 11, Rīga, LV-1050")
    end

    it "offers Register call and Edit for every call (UPD-05)", :aggregate_failures do
      call = create(:alarm_call, guarded_site: site)
      get root_path

      expect(response.parsed_body.at_css("a[href='#{new_call_path}']")&.text).to eq("Register call")
      expect(response.parsed_body.at_css("a[href='#{edit_call_path(call)}']")&.text).to eq("Edit")
    end

    it "listens to the stream the calls refresh and morphs the page (DYN-01)", :aggregate_failures do
      get root_path

      source = response.parsed_body.at_css("turbo-cable-stream-source[channel='Turbo::StreamsChannel']")
      expect(Turbo::StreamsChannel.verified_stream_name(source["signed-stream-name"])).to eq("board")
      expect(response.parsed_body.at_css("meta[name='turbo-refresh-method']")["content"]).to eq("morph")
    end
  end
end
