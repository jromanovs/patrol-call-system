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
    # A map that is built: without one the board draws no legend and no marks.
    allow(MapBuild).to receive(:new)
      .and_return(instance_double(MapBuild, current: "latvia-2026-10-02T142910Z.pmtiles", attempted_since?: false))
    english = I18n.backend.translations(do_init: true).fetch(:en)
    I18n.backend.store_translations(:zz, self.class.made_up(english))
    # The made-up language joins the languages of the system for the time of
    # an example; its own name makes it one that is offered (USR-10).
    I18n.backend.store_translations(:zz, language: { name: "¤¤" })
    I18n.available_locales = languages + [ :zz ]
  end

  after do
    I18n.available_locales = languages
    I18n.backend.reload!
  end

  let(:languages) { %i[ en lv ru ] }

  # The people and things the pages show. A name begins with a figure, so
  # that the initials drawn from it are no word of two letters.
  let(:world) do
    car = create(:patrol_car)
    site = create(:guarded_site)
    dispatcher = create(:user, name: "1 Dispatcher")
    # The call is registered by this dispatcher: the factory would make a further user with an English name.
    { administrator: create(:user, :administrator, name: "2 Administrator"), dispatcher: dispatcher,
      car: car, crew: create(:user, :crew, name: "3 Crew", patrol_car: car), site: site,
      call: create(:alarm_call, guarded_site: site, priority: :critical, registered_by: dispatcher) }
  end

  def dispatcher = world.fetch(:dispatcher)

  def car = world.fetch(:car)

  def site = world.fetch(:site)

  def call = world.fetch(:call)

  # What a record holds as data. The value of an enumeration and the kind of
  # a call are no data: shown as they are kept, they are words outside the files.
  def held_by(record)
    record.attributes.except("type", *record.class.defined_enums.keys).values.grep(String)
  end

  # The data of the records, the longest first, so that a part of a longer
  # value is not taken out of it before the whole; the name of the system; and
  # the address of the server, which the tracking page shows for the phones.
  def data
    held = [ Address, User, PatrolCar, GuardedSite, Call ].flat_map { |model| model.all.flat_map { |record| held_by(record) } }
    (held + [ "Patrol Call System", traccar_url ]).uniq.sort_by { |value| -value.length }
  end

  # The attributes whose words a user reads or hears, besides the text itself:
  # the stylesheet shows data-label as the name of a column in a narrow window,
  # the script of the map puts data-letter on a mark, and a script takes the
  # words it shows from attributes named …-text-value.
  def read_in_attributes(page)
    named = page.css("*").flat_map do |element|
      element.attributes.values.select { |attribute| attribute.name.match?(/\A(aria-label|title|placeholder|alt|data-turbo-confirm|data-label|data-letter|data-.*-text-value)\z/) }
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
        patch user_path(dispatcher), params: { user: { name: "4 Dispatcher" } }
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

  # A page has states the examples above do not reach: a part shown only after
  # a step, a refusal no example sends. So the files themselves are read too.
  # The reading knows the forms the views and the code use today; a word hidden
  # in another form is found only where a page that shows it is drawn above.
  describe "the files themselves" do
    def words?(text) = text.gsub(/\#\{.*?\}/, "").gsub("Patrol Call System", "").match?(/[A-Za-z]{2,}/)

    # Words as a sentence begins them: a capital letter and small ones, then
    # a space, a mark, an apostrophe or the end. A name of a class made of two
    # words, a key and a format are none; a string in small letters throughout
    # is not told from a key, and is found only on a drawn page.
    def sentence?(text) = text.gsub(/\#\{.*?\}/, "").gsub("Patrol Call System", "").match?(/(?:\A|[\s(])[A-Z][a-z]+(?:[\s.,:;!?…)'’]|\z)/)

    # The lines of a view that are no comment, each with its number and with
    # whether it goes on from the line before, as a list of attributes does.
    def lines_of(view)
      comment = nil
      open = false
      view.readlines(chomp: true).each_with_index.filter_map do |line, index|
        indent = line[/\A */].size
        next if line.strip.empty? || (comment && indent > comment)

        comment = line.strip.start_with?("-#", "/") ? indent : nil
        continued = open
        open = goes_on?(line.strip, continued)
        [ index + 1, line.strip, continued ] unless comment
      end
    end

    # A line of code goes on after a comma, an open bracket, a backslash, or
    # HAML's own sign for it, a bar after a space; the bar that ends `do |x|`
    # is none.
    def goes_on?(content, continued)
      return false unless continued || code?(content)

      content.end_with?(",", "(", "{", "[", "\\") || content.match?(/\s\|\z/) || content.count("{(") > content.count("})")
    end

    def code?(content) = content.start_with?("-", "=", "%", ".", "!", "&", "~", ":") || content.match?(/\A#[\w-]/)

    # The words a line of a view writes itself: after a tag, as a string for
    # a reader or a script, as a title, as the words of a link, a button or a
    # label, or as any string that reads as a sentence.
    def written_in(content)
      known = [ /\A(?:%[\w-]+|[.#][\w-]+)(?:[.#][\w-]+)*(?>\{.*\}|\(.*\))?[<>]*\s+(?![=~-])(.+)\z/,
                /\b(?:label|title|placeholder|alt|confirm|turbo_confirm|hint|prompt|include_blank|legend|\w+_text_value):\s*"([^"]*)"/,
                /content_for\(:title,\s*"([^"]*)"/, /\b(?:link_to|button_to|submit_tag|button_tag)\s*\(?\s*"([^"]*)"/,
                /\.(?:submit|label|button)\s+(?::\w+,\s*)?"([^"]*)"/, /\blabel_tag\s*\(?[^,"]+,\s*"([^"]*)"/ ]
      known.filter_map { |pattern| content[pattern, 1] }.find { |text| words?(text) } ||
        content.scan(/"([^"]*)"/).flatten.find { |text| sentence?(text) }
    end

    def own_words(view)
      lines_of(view).filter_map do |number, content, continued|
        plain = !continued && !code?(content) && words?(content)
        found = plain ? content : written_in(content)
        "#{view.relative_path_from(Rails.root)}:#{number} #{found}" if found
      end
    end

    it "no view writes a word of its own" do
      expect(Rails.root.glob("app/views/**/*.haml").flat_map { |view| own_words(view) }).to be_empty
    end

    # The words of the code of the pages: a refusal or a telling given as a
    # string, a value named by its own word, a plural made by hand, an error
    # that a page shows raised with words of its own, or a string that begins
    # with a capital word followed by a space, a mark or an apostrophe. A
    # single word and a string in small letters are not told from a name or a
    # key here; they are found only on a drawn page. A line of the server's
    # log is for whoever runs the server, as are the errors of other names,
    # and the name of the system is the same in every language.
    def worded?(line)
      return false if line.strip.start_with?("#", "-#") || line.include?("Rails.logger")

      line = line.gsub("Patrol Call System", "")
      line.match?(/errors\.add\([^)]*,\s*"|\bmessage:\s*"|\b(?:notice|alert):\s*"|\.humanize\b|\bpluralize\([^)]*"|"[A-Z][a-z]+(?:['’][a-z]+)?[ :;!?…][^"]*"/) ||
        line.match?(/\braise\s+(?:\w+::)*(?:Refused|Changed|Unavailable)\s*,\s*"/)
    end

    # The lines of a file with their numbers; of a view, without its comments.
    def code_of(file)
      return lines_of(file).map { |number, content, _| [ number, content ] } if file.extname == ".haml"

      file.readlines.each_with_index.map { |line, index| [ index + 1, line ] }
    end

    # The JSON API speaks to programs and keeps its own messages; the
    # services named here load data and speak to whoever runs the server.
    it "no model, helper, service or controller of the pages words a refusal or a telling, or names a value by its own word" do
      apart = %r{/controllers/api/|/services/(?:map_build|demo_data|demo_calls|address_register_load)\.rb}
      files = Rails.root.glob("app/{models,controllers,services,helpers,views}/**/*.{rb,haml}").reject { |file| file.to_s.match?(apart) }
      found = files.flat_map do |file|
        code_of(file).filter_map { |number, line| "#{file.relative_path_from(Rails.root)}:#{number}" if worded?(line) }
      end

      expect(found).to be_empty
    end
  end

  # A key built from a value needs a text for every value it can be built from.
  it "a text for every value where a key is built from one", :aggregate_failures do
    built = { "models.patrol_car.tracked" => PatrolCar.position_sources.keys, "trackings.sources" => PatrolCar.position_sources.keys,
              "maps.arrivals" => MapsHelper::ARRIVALS, "crews.show.further_car" => %w[ sent on-the-way on-site far ],
              "services.call_step.not_possible" => Call::ACTIVE.map(&:to_s) }

    built.each { |key, values| expect(I18n.t(key, locale: :en, default: {}).keys.map(&:to_s)).to match_array(values), key }
  end

  it "the names of every value of every enumeration", :aggregate_failures do
    Rails.application.eager_load!
    names = I18n.t("enums", locale: :en, default: {})
    models = ApplicationRecord.descendants.reject(&:abstract_class?).select { |model| model.defined_enums.any? }

    expect(models.size).to be >= 8
    models.each do |model|
      model.defined_enums.each do |attribute, values|
        named = names.dig(model.base_class.model_name.i18n_key, attribute.to_sym) || names.dig(model.model_name.i18n_key, attribute.to_sym)
        expect(named&.keys&.map(&:to_s)).to eq(values.keys), "#{model}.#{attribute}"
      end
    end
  end
end
