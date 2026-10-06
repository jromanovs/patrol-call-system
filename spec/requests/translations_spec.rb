require "rails_helper"

# Every text a user reads comes from the translation files. The pages are
# drawn here in a made-up language, built from the English files with every
# letter replaced by a sign. A plain word left on a page is one that stands
# in no translation file. Data are taken away first: what the records hold,
# and the name of the system, which is the same in every language.
RSpec.describe "Texts from the translation files" do
  def self.made_up(node)
    case node
    when Hash then node.transform_values { |value| made_up(value) }
    when Array then node.map { |value| made_up(value) }
    when String
      # A format of a date or a number is no text: its letters are orders.
      return node if node.match?(/%[-0-9^#]*[a-zA-Z]/) && node.exclude?("%{")

      node.gsub(/%\{\w+\}|<[^>]+>|&\w+;|[A-Za-z]/) { |part| part.length > 1 ? part : "¤" }
    else node
    end
  end

  before do
    english = I18n.backend.translations(do_init: true).fetch(:en)
    I18n.backend.store_translations(:zz, self.class.made_up(english))
    # The list of languages is remembered from the first text asked for; it is
    # read again, so that the made-up one counts after other examples have run.
    I18n.config.clear_available_locales_set
  end

  # The people and things the pages show, named so that their initials are
  # no plain letters either.
  let(:world) do
    car = create(:patrol_car)
    site = create(:guarded_site)
    dispatcher = create(:user, name: "Первый Диспетчер")
    # The call is registered by this dispatcher: the factory would make a further user with an English name.
    { administrator: create(:user, :administrator, name: "Старший Администратор"), dispatcher: dispatcher,
      car: car, crew: create(:user, :crew, name: "Экипаж Один", patrol_car: car), site: site,
      call: create(:alarm_call, guarded_site: site, priority: :critical, registered_by: dispatcher) }
  end

  def dispatcher = world.fetch(:dispatcher)

  def car = world.fetch(:car)

  def site = world.fetch(:site)

  def call = world.fetch(:call)

  # What the records hold, the longest first, so that a part of a longer
  # value is not taken out of it before the whole; the name of the system; and
  # the address of the server, which the tracking page shows for the phones.
  def data
    held = [ Address, User, PatrolCar, GuardedSite, Call ].flat_map { |model| model.all.flat_map { |record| record.attributes.values.grep(String) } }
    (held + [ "Patrol Call System", traccar_url ]).uniq.sort_by { |value| -value.length }
  end

  # The attributes whose words a user reads or hears, besides the text itself;
  # a script takes the words it shows from attributes named …-text-value.
  def read_in_attributes(page)
    named = page.css("*").flat_map do |element|
      element.attributes.values.select { |attribute| attribute.name.match?(/\A(aria-label|title|placeholder|alt|data-turbo-confirm|data-.*-text-value)\z/) }
    end
    named.map(&:value) + page.css("input[type=submit], input[type=button]").map { |button| button["value"].to_s }
  end

  # The plain words left on the page. Scripts and styles are no text of it.
  def plain_words
    page = Nokogiri::HTML5(response.body)
    page.css("script, style, template").each(&:remove)
    text = ([ page.text ] + read_in_attributes(page)).join("\n")
    data.each { |value| text = text.gsub(value, " ") }
    text.scan(/[A-Za-z]{2,}(?: [A-Za-z]{2,})*/).uniq
  end

  # What is wrong with a page drawn in the made-up language: it does not
  # answer, a text is missing from the files, or plain words are left.
  def wrong_with(status = :ok)
    return [ "answered #{response.status}" ] unless response.status == Rack::Utils.status_code(status)

    response.parsed_body.css(".translation_missing").map { |missing| missing["title"] } + plain_words.first(12)
  end

  def left_on(*paths)
    paths.to_h { |path| [ path, I18n.with_locale(:zz) { get(path) }.then { wrong_with } ] }.reject { |_, wrong| wrong.empty? }
  end

  def left_after_refusal(path, params)
    I18n.with_locale(:zz) { post path, params: params }
    wrong_with(:unprocessable_content)
  end

  it "the sign-in page" do
    expect(left_on(new_session_path)).to be_empty
  end

  context "when signed in as an administrator" do
    before { sign_in_as(world.fetch(:administrator)) }

    it "the board with its map" do
      expect(left_on(root_path)).to be_empty
    end

    it "the calls: the list, a call, its form" do
      expect(left_on(calls_path, call_path(call), new_call_path, edit_call_path(call))).to be_empty
    end

    it "the dialogs of a call that waits: send a car, cancel; and of the old calls" do
      expect(left_on(new_call_dispatch_path(call), new_call_cancellation_path(call), new_call_cleanup_path)).to be_empty
    end

    it "a call with its car sent, accepted, on site and closed, and the dialogs of those steps", :aggregate_failures do
      CallStep.new(call, dispatcher).dispatch(car)
      expect(left_on(root_path, call_path(call), new_call_backup_path(call))).to be_empty
      CallStep.new(call.reload, dispatcher).accept
      expect(left_on(call_path(call))).to be_empty
      CallStep.new(call.reload, dispatcher).arrive
      expect(left_on(call_path(call), new_call_closing_path(call))).to be_empty
      CallStep.new(call.reload, dispatcher).close("other", "")
      expect(left_on(call_path(call), calls_path, statistics_path)).to be_empty
    end

    it "a crew's SOS on the board and on its page" do
      sos = create(:sos_call, raised_by: car)

      expect(left_on(root_path, call_path(sos), calls_path)).to be_empty
    end

    it "the sites: the list, a site, its form" do
      expect(left_on(guarded_sites_path, guarded_site_path(site), new_guarded_site_path, edit_guarded_site_path(site))).to be_empty
    end

    it "the cars: the list, a car, its form" do
      expect(left_on(patrol_cars_path, patrol_car_path(car), new_patrol_car_path, edit_patrol_car_path(car))).to be_empty
    end

    it "the statistics, the tracking and the settings" do
      create(:car_position, patrol_car: car)

      expect(left_on(statistics_path, tracking_path, settings_path)).to be_empty
    end

    it "the users: the list, the forms, the dialog of a password" do
      pages = [ users_path, new_user_path, edit_user_path(dispatcher), edit_user_path(world.fetch(:administrator)),
                edit_user_password_path(world.fetch(:crew)) ]

      expect(left_on(*pages)).to be_empty
    end

    it "the user's own pages: the profile, the password, the picture, the API key" do
      expect(left_on(profile_path, edit_password_path, edit_profile_picture_path, api_key_path)).to be_empty
    end

    it "what a form answers when it is refused", :aggregate_failures do
      expect(left_after_refusal(users_path, { user: { name: "", email_address: "", password: "short", role: "crew" } })).to be_empty
      expect(left_after_refusal(guarded_sites_path, { guarded_site: { name: "" } })).to be_empty
      expect(left_after_refusal(patrol_cars_path, { patrol_car: { call_sign: "" } })).to be_empty
      expect(left_after_refusal(calls_path, { call: { kind: "alarm", guarded_site_id: "" } })).to be_empty
    end

    it "what is told after an action" do
      I18n.with_locale(:zz) do
        patch user_path(dispatcher), params: { user: { name: "Второй Диспетчер" } }
        follow_redirect!
      end

      expect(wrong_with).to be_empty
    end
  end

  context "when signed in as a crew" do
    before { sign_in_as(world.fetch(:crew)) }

    it "the crew's screen with no call, the dialog of an SOS, the profile" do
      expect(left_on(crew_path, new_crew_sos_path, profile_path)).to be_empty
    end

    it "the crew's screen through the steps of its call", :aggregate_failures do
      CallStep.new(call, dispatcher).dispatch(car)
      expect(left_on(crew_path)).to be_empty
      CallStep.new(call.reload, dispatcher).accept
      expect(left_on(crew_path)).to be_empty
      CallStep.new(call.reload, dispatcher).arrive
      expect(left_on(crew_path)).to be_empty
    end
  end

  it "the names of every enumeration", :aggregate_failures do
    names = I18n.t("enums", locale: :en, default: {})

    { User => %i[ role theme ], Call => %i[ status priority ], PatrolCar => %i[ status ], GuardedSite => %i[ site_type district ] }
      .each do |model, attributes|
      attributes.each do |attribute|
        values = model.public_send(attribute.to_s.pluralize).keys
        expect(names.dig(model.model_name.i18n_key, attribute)&.keys&.map(&:to_s)).to eq(values), "#{model}.#{attribute}"
      end
    end
  end
end
