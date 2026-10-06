require "rails_helper"

RSpec.describe "A text sent to other people is in the language of its reader (USR-10)" do
  include_context "without the seeded records"

  let(:car) { create(:patrol_car, call_sign: "P-12") }
  let(:sent) { {} }

  def asking_for(languages) = { "HTTP_ACCEPT_LANGUAGE" => languages }

  # Latvian and Russian are given here by hand, with a word of each text that
  # goes to other people than the one who caused it.
  before do
    I18n.backend.store_translations(:lv, language: { name: "Latviešu" }, sos_calls: { strips: { no_sound: "Skaņas vēl nav" } },
                                         services: { crew_notice: { title: "Izsaukums: %{place}",
                                                                    reminder_title: "Atgādinājums %{number}: %{place}" } })
    I18n.backend.store_translations(:ru, language: { name: "Русский" }, sos_calls: { strips: { no_sound: "Звука пока нет" } },
                                         services: { crew_notice: { title: "Вызов: %{place}",
                                                                    reminder_title: "Напоминание %{number}: %{place}" } })
    allow(WebPush).to receive(:payload_send) { |**notice| sent[notice[:endpoint]] = JSON.parse(notice[:message])["title"] }
    allow(MapBuild).to receive(:new).and_return(instance_double(MapBuild, current: "demo.pmtiles", attempted_since?: true))
  end

  after { I18n.backend.reload! }

  describe "the strip of a crew's SOS (DSP-06, DYN-19)" do
    def streams
      response.parsed_body.css("turbo-cable-stream-source")
              .map { |source| Turbo::StreamsChannel.verified_stream_name(source["signed-stream-name"]) }
    end

    it "reaches the pages of each language in that language, whatever the language of the crew that asked" do
      sign_in_as(create(:user, :crew, patrol_car: car, locale: "lv"))

      expect { post crew_sos_path, params: { latitude: 56.95, longitude: 24.1, accuracy: 12 } }
        .to have_broadcasted_to("sos:en").with(a_string_including("SOS from P-12", "No sound yet"))
        .and have_broadcasted_to("sos:lv").with(a_string_including("Skaņas vēl nav"))
        .and have_broadcasted_to("sos:ru").with(a_string_including("Звука пока нет"))
    end

    it "is taken off the pages of each language, whatever the language of whoever acknowledged it" do
      call = create(:sos_call, raised_by: car)
      sign_in_as(create(:user, locale: "ru"))

      expect { post call_acknowledgement_path(call) }
        .to have_broadcasted_to("sos:en").with(a_string_including("No sound yet"))
        .and have_broadcasted_to("sos:lv").with(a_string_including("Skaņas vēl nav"))
        .and have_broadcasted_to("sos:ru").with(a_string_including("Звука пока нет"))
    end

    it "goes to no page without its language" do
      expect { SosCall.show_strips }.not_to have_broadcasted_to("sos")
    end

    it "leaves the language of the request that caused it as it was" do
      I18n.with_locale(:lv) do
        SosCall.show_strips

        expect(I18n.locale).to eq(:lv)
      end
    end

    it "is listened for by a page of the staff in the language of that page alone", :aggregate_failures do
      sign_in_as(create(:user, locale: "lv"))
      get calls_path
      expect(streams.grep(/\Asos/)).to eq(%w[ sos:lv ])

      Current.user.update!(locale: nil)
      get calls_path, headers: asking_for("ru")
      expect(streams.grep(/\Asos/)).to eq(%w[ sos:ru ])

      get calls_path
      expect(streams.grep(/\Asos/)).to eq(%w[ sos:en ])
    end
  end

  describe "the notice on a crew's phone (CRW-04, CRW-06)" do
    let(:call) { create(:alarm_call, guarded_site: create(:guarded_site, name: "Demo Office 1"), priority: :critical) }

    # A phone of the car's crew: the language its user chose, and the
    # language of the crew screen it was last sent from.
    def phone(chosen: nil, seen: nil)
      create(:push_subscription, locale: seen, user: create(:user, :crew, patrol_car: car, locale: chosen)).endpoint
    end

    def dispatch_as(dispatcher)
      sign_in_as(dispatcher)
      perform_enqueued_jobs(only: CrewNoticeJob) { post call_dispatch_path(call), params: { patrol_car_id: car.id } }
    end

    it "is worded for each phone of a car in the language its user chose, whatever the language of the dispatcher" do
      latvian, russian, english = phone(chosen: "lv"), phone(chosen: "ru"), phone(chosen: "en")
      dispatch_as(create(:user, locale: "ru"))

      expect(sent).to eq(latvian => "Izsaukums: Demo Office 1", russian => "Вызов: Demo Office 1",
                         english => "Critical call: Demo Office 1")
    end

    it "is worded without a choice in the language of the crew screen the phone was last sent from, and else in English" do
      seen, chosen, neither = phone(seen: "lv"), phone(chosen: "ru", seen: "lv"), phone
      dispatch_as(create(:user, locale: "ru"))

      expect(sent).to eq(seen => "Izsaukums: Demo Office 1", chosen => "Вызов: Demo Office 1",
                         neither => "Critical call: Demo Office 1")
    end

    it "is worded in the next language of the phone when one is offered no more" do
      chosen, seen = phone(chosen: "ru", seen: "lv"), phone(seen: "ru")
      allow(Language).to receive(:offered).and_return(%w[ en lv ])
      dispatch_as(create(:user))

      expect(sent).to eq(chosen => "Izsaukums: Demo Office 1", seen => "Critical call: Demo Office 1")
    end

    it "is reminded of in the same language, by a job that the request of a dispatcher queued" do
      latvian, english = phone(chosen: "lv"), phone
      sign_in_as(create(:user, locale: "ru"))
      post call_dispatch_path(call), params: { patrol_car_id: car.id }
      perform_enqueued_jobs(only: CrewReminderJob, at: 1.minute.from_now)

      expect(sent).to eq(latvian => "Atgādinājums 1: Demo Office 1", english => "Reminder 1 — Critical call: Demo Office 1")
    end

    it "is told to the crew of a further car in the language of each of its phones (BR-22)" do
      CallStep.new(call, create(:user)).dispatch(create(:patrol_car))
      latvian, english = phone(seen: "lv"), phone
      sign_in_as(create(:user, locale: "ru"))
      perform_enqueued_jobs(only: CrewNoticeJob) { post call_backups_path(call), params: { patrol_car_id: car.id } }

      expect(sent).to eq(latvian => "Izsaukums: Demo Office 1", english => "Critical call: Demo Office 1")
    end
  end

  describe "a phone that turns the notices on (CRW-04)" do
    let(:crew) { create(:user, :crew, patrol_car: car) }
    let(:subscription) do
      { endpoint: "https://fcm.googleapis.com/fcm/send/phone-1",
        keys: { p256dh: "BJA-ASKgnz7Tc9fjAtRcHgoLxY_4PoTzJRRoy5d7oL-wUGj-tIBVAOARalAcG1eBO39yrcSeYW1JtuFOWdgDg5c",
                auth: "tBHItJI5svbpez7KI4CCXg==" } }
    end

    def subscribe(asking: nil) = post(push_subscription_path, params: subscription, as: :json, headers: asking_for(asking))

    before { sign_in_as(crew) }

    it "is kept with the language of the crew screen it was sent from, each time it is sent", :aggregate_failures do
      subscribe(asking: "lv")
      expect(PushSubscription.sole.locale).to eq("lv")

      subscribe(asking: "de")
      expect(PushSubscription.sole.locale).to eq("en")

      crew.update!(locale: "ru")
      subscribe(asking: "lv")
      expect(PushSubscription.sole.locale).to eq("ru")
    end

    it "keeps no language that is sent with it" do
      post push_subscription_path, params: subscription.merge(locale: "ru"), as: :json

      expect(PushSubscription.sole.locale).to eq("en")
    end
  end
end
