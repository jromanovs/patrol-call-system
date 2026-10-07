require "rails_helper"

RSpec.describe "Field checks before a form is sent (DYN-09)" do
  include_context "without the seeded records"

  before { sign_in_as(create(:user)) }

  def page(path)
    get path
    response.parsed_body
  end

  # What a field tells the script that checks it.
  def carried(page, id) = page.at_css("##{id}").to_h.select { |name, _| name.start_with?("data-check-") }

  # The form hears a field being left and a value being changed.
  def listening?(page)
    form = page.at_css("form.form")
    form["data-controller"].to_s.split.include?("check") &&
      form["data-action"].to_s.split.to_set.superset?(%w[ focusout->check#leave input->check#mend ].to_set)
  end

  it "gives the form of a site the rules of the contract number and of the keyholder's phone", :aggregate_failures do
    form = page(new_guarded_site_path)

    expect(listening?(form)).to be(true)
    expect(carried(form, "guarded_site_contract_number"))
      .to eq("data-check-pattern" => "^C-\\d{5}$", "data-check-message" => "Contract number is invalid")
    expect(carried(form, "guarded_site_keyholder_phone"))
      .to eq("data-check-pattern" => "^\\+\\d{8,15}$", "data-check-message" => "Keyholder phone is invalid")
    expect(carried(form, "guarded_site_name")).to be_empty
  end

  it "gives the form of a car the rules of the call sign, of the plate number and of the crew", :aggregate_failures do
    form = page(new_patrol_car_path)

    expect(listening?(form)).to be(true)
    expect(carried(form, "patrol_car_call_sign"))
      .to eq("data-check-pattern" => "^[A-Z]{1,3}-\\d{1,3}$", "data-check-message" => "Call sign is invalid")
    expect(carried(form, "patrol_car_plate_number")).to eq(
      "data-check-pattern" => "^[A-Z0-9-]{2,10}$", "data-check-message" => "Plate number is invalid",
      "data-check-trim" => "true", "data-check-upper" => "true"
    )
    expect(carried(form, "patrol_car_crew_size")).to eq(
      "data-check-least" => "1", "data-check-most" => "4", "data-check-message" => "Crew size must be between 1 and 4"
    )
  end

  # DYN-04: the form of a call holds the fields of both types.
  it "gives the form of a call the rules of the sensor zone and of the caller's phone, beside its own script", :aggregate_failures do
    create(:guarded_site)
    form = page(new_call_path)

    expect(listening?(form)).to be(true)
    expect(form.at_css("form.form")["data-controller"].split).to include("call-form")
    expect(carried(form, "call_sensor_zone"))
      .to eq("data-check-least" => "1", "data-check-most" => "99", "data-check-message" => "Sensor zone must be from 1 to 99")
    expect(carried(form, "call_caller_phone"))
      .to eq("data-check-pattern" => "^\\+\\d{8,15}$", "data-check-message" => "Caller phone is invalid")
  end

  it "gives the same rules when a car or a site is changed", :aggregate_failures do
    car = create(:patrol_car)
    site = create(:guarded_site)

    expect(carried(page(edit_patrol_car_path(car)), "patrol_car_call_sign")).to include("data-check-pattern")
    expect(carried(page(edit_guarded_site_path(site)), "guarded_site_contract_number")).to include("data-check-pattern")
  end

  it "words a rule's message in the language of the reader" do
    get new_patrol_car_path, headers: { "Accept-Language" => "lv" }
    words = I18n.with_locale(:lv) { PatrolCar.new(crew_size: 9).tap(&:valid?).errors.full_messages_for(:crew_size).sole }

    expect(carried(response.parsed_body, "patrol_car_crew_size")["data-check-message"]).to eq(words)
  end
end
