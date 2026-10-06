require "rails_helper"

# USR-10: the application in Latvian and in Russian. The English files say
# which texts there are; the two languages have each of them, worded by the
# terms agreed for the things of the system.
RSpec.describe "TranslationFiles" do
  # What is the same in every language: a name, a unit, a code.
  def same = /\A(?:[^A-Za-z]|%\{\w+\}|<[^>]+>|SOS|API|Traccar(?: Client)?|Google|Gravatar|ALTCHA|Altcha|OpenMapTiles|OpenStreetMap|min|km|m|EN|LV|RU|OK)*\z/

  def counted?(node) = node.is_a?(Hash) && node.any? && (node.keys - %w[ zero one two few many other ]).empty?

  def leaves(node, path = [])
    return { path.join(".") => node } if !node.is_a?(Hash) || counted?(node)

    node.reduce({}) { |found, (key, value)| found.merge(leaves(value, path + [ key ])) }
  end

  # The texts of the application's own files of a language, each by its key;
  # a text with a count is kept whole, with its forms.
  def texts(language)
    Rails.root.glob("config/locales/#{language}{.yml,/*.yml}").map { |file| YAML.load_file(file).fetch(language) }
         .reduce({}) { |all, tree| all.merge(leaves(tree)) }
  end

  def english = @english ||= texts("en")

  def places(text) = text.to_s.scan(/%\{\w+\}/).uniq.sort

  def markup(text) = text.to_s.scan(%r{</?[a-z][a-z0-9]*}i).sort

  # A format of a date is an order, the same in every language (BR-10).
  def worded(own) = own.select { |key, _| english[key].is_a?(String) && key.exclude?(".formats.") }

  shared_examples "a language of the application" do |language, terms|
    let(:own) { texts(language) }

    it "has a text for every key of the English files, and none left over", :aggregate_failures do
      expect(english.keys - own.keys).to be_empty
      # The standard messages of Rails may be worded anew for a language: its gem words them for a masculine name.
      expect((own.keys - english.keys).reject { |key| key.start_with?("errors.messages.") }).to be_empty
      expect(own.select { |_, text| text.is_a?(String) && text.strip.empty? }.keys).to be_empty
    end

    # A form that is missing would be replaced by the form "other" without a word of warning.
    it "gives a text with a count the form of every number, by the rule of the language" do
      rule = I18n.t(:"i18n.plural.rule", locale: language, resolve: false)
      needed = [ *0..200, 1.5 ].map { |count| rule.call(count).to_s }.uniq
      without = english.select { |_, text| counted?(text) }.keys.reject { |key| own[key].is_a?(Hash) && (needed - own[key].keys).empty? }

      expect([ needed.size > 1, without ]).to eq([ true, [] ])
    end

    it "keeps the places for data of each English text, and the markup of a text with markup", :aggregate_failures do
      expect(worded(own).reject { |key, text| places(text) == places(english[key]) }.keys).to be_empty
      expect(worded(own).select { |key, text| key.end_with?("_html") && markup(text) != markup(english[key]) }.keys).to be_empty
    end

    it "leaves no text as it is in English, but what is the same in every language" do
      expect(worded(own).select { |key, text| text == english[key] && !text.match?(same) }).to be_empty
    end

    it "names the things of the system by the agreed terms" do
      named = terms.to_h { |scope, words| [ scope, words.to_h { |key, _| [ key, own["#{scope}.#{key}"] ] } ] }

      expect(named).to eq(terms)
    end

    # BR-10: the standard texts of the gem have formats of their own for each language.
    it "writes a date and a time as the English pages do" do
      moment = Time.zone.local(2026, 10, 6, 9, 5)

      expect([ I18n.l(moment, locale: language), I18n.l(moment.to_date, locale: language) ]).to eq([ "06.10.2026 09:05", "06.10.2026" ])
    end
  end

  describe "Latvian" do
    it_behaves_like "a language of the application", "lv", {
      "enums.call.priority" => { "low" => "Zema", "normal" => "Parasta", "high" => "Augsta", "critical" => "Kritiska" },
      "enums.call.status" => { "pending" => "Gaida", "dispatched" => "Grupa nosūtīta", "accepted" => "Pieņemts", "on_scene" => "Uz vietas",
                               "closed" => "Slēgts", "cancelled" => "Atcelts" },
      "enums.patrol_car.status" => { "available" => "Brīva", "out_of_service" => "Nav dienestā" },
      "enums.alarm_call.alarm_type" => { "intrusion" => "Ielaušanās", "fire" => "Ugunsgrēks", "panic" => "Panikas poga",
                                         "tamper" => "Iekārtas atvēršana", "power_failure" => "Elektroapgādes traucējums" },
      "enums.call.outcome" => { "false_alarm" => "Viltus trauksme", "intrusion_confirmed" => "Ielaušanās apstiprināta",
                                "fire_confirmed" => "Ugunsgrēks apstiprināts", "technical_fault" => "Tehniska kļūme",
                                "help_given" => "Palīdzība sniegta", "other" => "Cits" },
      "enums.user.role" => { "dispatcher" => "Dispečers", "supervisor" => "Maiņas vadītājs", "administrator" => "Administrators",
                             "crew" => "Mobilā grupa" },
      "application.menu" => { "calls" => "Izsaukumi", "sites" => "Objekti", "cars" => "Automašīnas", "statistics" => "Statistika" },
      "application.account" => { "users" => "Lietotāji", "tracking" => "Izsekošana", "settings" => "Iestatījumi", "profile" => "Profils",
                                 "sign_out" => "Iziet" },
      "calls.steps" => { "dispatch" => "Nosūtīt grupu", "accepted" => "Pieņemts", "arrived" => "Ieradās", "close" => "Slēgt",
                         "cancel" => "Atcelt", "send_another" => "Nosūtīt vēl vienu grupu" },
      "calls.index" => { "register" => "Reģistrēt izsaukumu" }, "sessions.new" => { "submit" => "Ieiet" },
      "language" => { "name" => "Latviešu" }
    }

    it "has no Cyrillic letter" do
      expect(texts("lv").select { |_, text| text.to_s.match?(/\p{Cyrillic}/) }.keys).to be_empty
    end
  end

  describe "Russian" do
    it_behaves_like "a language of the application", "ru", {
      "enums.call.priority" => { "low" => "Низкий", "normal" => "Обычный", "high" => "Высокий", "critical" => "Критический" },
      "enums.call.status" => { "pending" => "Ожидает", "dispatched" => "Машина отправлена", "accepted" => "Принят", "on_scene" => "На месте",
                               "closed" => "Закрыт", "cancelled" => "Отменён" },
      "enums.patrol_car.status" => { "available" => "Свободна", "out_of_service" => "Не на службе" },
      "enums.alarm_call.alarm_type" => { "intrusion" => "Проникновение", "fire" => "Пожар", "panic" => "Тревожная кнопка",
                                         "tamper" => "Вскрытие устройства", "power_failure" => "Отключение питания" },
      "enums.call.outcome" => { "false_alarm" => "Ложная тревога", "intrusion_confirmed" => "Проникновение подтверждено",
                                "fire_confirmed" => "Пожар подтверждён", "technical_fault" => "Техническая неисправность",
                                "help_given" => "Помощь оказана", "other" => "Другое" },
      "enums.user.role" => { "dispatcher" => "Диспетчер", "supervisor" => "Старший смены", "administrator" => "Администратор",
                             "crew" => "Экипаж" },
      "application.menu" => { "calls" => "Вызовы", "sites" => "Объекты", "cars" => "Машины", "statistics" => "Статистика" },
      "application.account" => { "users" => "Пользователи", "tracking" => "Слежение", "settings" => "Настройки", "profile" => "Профиль",
                                 "sign_out" => "Выйти" },
      "calls.steps" => { "dispatch" => "Отправить машину", "accepted" => "Принят", "arrived" => "Прибыл", "close" => "Закрыть",
                         "cancel" => "Отменить", "send_another" => "Отправить ещё машину" },
      "calls.index" => { "register" => "Зарегистрировать вызов" }, "sessions.new" => { "submit" => "Войти" },
      "language" => { "name" => "Русский" }
    }

    it "is written in Cyrillic, but what is the same in every language" do
      expect(worded(texts("ru")).reject { |_, text| text.match?(same) || text.match?(/\p{Cyrillic}/) }).to be_empty
    end
  end
end
