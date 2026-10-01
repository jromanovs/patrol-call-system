require "rails_helper"

RSpec.describe "Alarm calls" do
  let(:dispatcher) { create(:user) }
  let(:site) { create(:guarded_site, name: "Warehouse No. 3", contract_number: "C-00042") }
  let(:fields) { { guarded_site_id: site.id, alarm_type: "panic", sensor_zone: "1" } }

  before { sign_in_as(dispatcher) }

  it "gives every field of the alarm call form a label and a hint" do
    get new_call_path

    expect(fields_without_label_or_hint(response.parsed_body)).to be_empty
  end

  it "offers only sites with an active contract (BR-1)", :aggregate_failures do
    site
    create(:guarded_site, :suspended, name: "Closed Shop")
    get new_call_path

    options = response.parsed_body.css("#alarm_call_guarded_site_id option").map(&:text).join(" | ")
    expect(options).to include("Warehouse No. 3 · C-00042")
    expect(options).not_to include("Closed Shop")
  end

  it "registers an alarm call and returns to the board (ADD-05)", :aggregate_failures do
    expect { post calls_path, params: { alarm_call: fields } }.to change(AlarmCall, :count).by(1)

    expect(response).to redirect_to(root_path)
    expect(flash[:notice]).to eq("Alarm call registered")
    expect(AlarmCall.last).to have_attributes(status: "pending", priority: "critical", guarded_site: site,
                                              registered_by: dispatcher)
  end

  it "refuses zones 0 and 100 with a message at the field and saves nothing (ADD-06)", :aggregate_failures do
    %w[0 100].each do |zone|
      expect { post calls_path, params: { alarm_call: fields.merge(sensor_zone: zone) } }.not_to change(Call, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body.at_css("#alarm_call_sensor_zone_error")&.text).to eq("Sensor zone must be from 1 to 99")
    end
  end

  it "refuses a time of receipt one minute ahead (ADD-06)", :aggregate_failures do
    freeze_time do
      received_at = 1.minute.from_now.strftime("%Y-%m-%dT%H:%M")
      expect { post calls_path, params: { alarm_call: fields.merge(received_at:) } }.not_to change(Call, :count)

      expect(response.parsed_body.at_css("#alarm_call_received_at_error")&.text).to eq("Time received cannot be in the future")
    end
  end

  it "refuses a site whose contract is suspended (BR-1)" do
    closed = create(:guarded_site, :suspended)

    expect { post calls_path, params: { alarm_call: fields.merge(guarded_site_id: closed.id) } }.not_to change(Call, :count)
  end

  describe "the board" do
    it "shows a call with priority, site, alarm, status, waiting time and time received (DSP-03)", :aggregate_failures do
      travel_to Time.zone.local(2026, 10, 1, 15, 45) do
        create(:alarm_call, guarded_site: site, alarm_type: :fire, sensor_zone: 7, received_at: 13.minutes.ago)
        get root_path
      end

      row = response.parsed_body.at_css("table.data-table tbody tr")
      cells = row.css("td").to_h { |cell| [ cell["data-label"], cell.text.squish ] }
      expect(row["class"]).to include("critical")
      expect(cells).to include("Priority" => "Critical", "Call" => "Alarm: fire Zone 7", "Status" => "Pending",
                               "Waiting" => "13 min 01.10.2026 15:32")
      expect(cells["Site"]).to eq("Warehouse No. 3 C-00042 · Jēkaba iela 11, Rīga, LV-1050")
    end

    it "offers Register call" do
      get root_path

      expect(response.parsed_body.at_css("a[href='#{new_call_path}']")&.text).to eq("Register call")
    end

    it "listens to the stream the calls refresh and morphs the page (DYN-01)", :aggregate_failures do
      get root_path

      source = response.parsed_body.at_css("turbo-cable-stream-source[channel='Turbo::StreamsChannel']")
      expect(Turbo::StreamsChannel.verified_stream_name(source["signed-stream-name"])).to eq("board")
      expect(response.parsed_body.at_css("meta[name='turbo-refresh-method']")["content"]).to eq("morph")
    end
  end
end
