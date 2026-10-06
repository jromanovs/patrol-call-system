require "rails_helper"

RSpec.describe "The language of the pages (USR-10)" do
  let(:user) { create(:user, name: "Demo Dispatcher") }

  def page = response.parsed_body

  def language = page.at_css("html")["lang"]

  def asking_for(languages) = { "HTTP_ACCEPT_LANGUAGE" => languages }

  # A language is offered once its own file gives its name. The files of the
  # application are English; two further languages are given here by hand,
  # with one word of the header each, so that a page shows which it is in.
  def offer_latvian_and_russian
    I18n.backend.store_translations(:lv, language: { name: "Latviešu" }, application: { menu: { calls: "Izsaukumi" } },
                                         common: { not_allowed: "Jūsu lomai nav atļauts" })
    I18n.backend.store_translations(:ru, language: { name: "Русский" }, application: { menu: { calls: "Вызовы" } })
  end

  after { I18n.backend.reload! }

  it "knows English, Latvian and Russian, with the standard texts and the plural forms of each", :aggregate_failures do
    expect(I18n.available_locales).to eq(%i[ en lv ru ])
    expect(I18n.t("date.month_names", locale: :lv)[1]).to eq("janvārī")
    expect(I18n.t("errors.messages.blank", locale: :ru)).to eq("не может быть пустым")
    I18n.backend.store_translations(:ru, forms: { one: "one", few: "few", many: "many", other: "other" })
    I18n.backend.store_translations(:lv, forms: { one: "one", other: "other" })
    expect([ 1, 3, 5, 21 ].map { |count| I18n.t("forms", count:, locale: :ru) }).to eq(%w[ one few many one ])
    expect([ 1, 2, 11, 21 ].map { |count| I18n.t("forms", count:, locale: :lv) }).to eq(%w[ one other other one ])
  end

  # On the site a text missing from a language is shown in English. Asked for
  # in that way, the English name would stand in for the name of every other
  # language, and each would be offered before it has a text of its own.
  it "asks for the name of a language without English standing in for it" do
    allow(I18n).to receive(:t).and_call_original
    Language.offered

    expect(I18n).to have_received(:t).with("language.name", hash_including(locale: "lv", fallback: false))
  end

  context "with English alone, as the files stand" do
    before { sign_in_as(user) }

    it "draws every page in English whatever the browser asks for, and offers no choice", :aggregate_failures do
      get root_path, headers: asking_for("lv,ru;q=0.9")

      expect(language).to eq("en")
      expect(page.at_css("header .language-button, header #language-menu")).to be_nil
    end

    it "keeps to English for a user whose language is offered no more" do
      user.update_column(:locale, "lv")
      get root_path

      expect(language).to eq("en")
    end

    it "refuses a language that is not offered, and changes nothing", :aggregate_failures do
      patch language_path, params: { language: "lv" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(user.reload.locale).to be_nil
    end
  end

  context "with Latvian and Russian offered too" do
    before { offer_latvian_and_russian }

    it "draws the sign-in page in the first offered language the browser asks for, and in English otherwise", :aggregate_failures do
      { "lv" => "lv", "ru-RU,ru;q=0.9,en;q=0.8" => "ru", "de,lv;q=0.5,en;q=0.9" => "en", "lv;q=0.2,ru;q=0.7" => "ru",
        "de" => "en", "*" => "en", "" => "en", "lv;q=0" => "en", ",,;q=x" => "en" }.each do |asked, drawn|
        get new_session_path, headers: asking_for(asked)
        expect(language).to eq(drawn), asked.inspect
      end
      get new_session_path
      expect(language).to eq("en")
      expect(page.at_css("header .language-button")).to be_nil
    end

    it "asks a visitor who is not signed in to sign in" do
      patch language_path, params: { language: "lv" }

      expect(response).to redirect_to(new_session_path)
    end

    context "when signed in" do
      before { sign_in_as(user) }

      it "follows the browser until the user chooses", :aggregate_failures do
        get root_path, headers: asking_for("lv")

        expect(language).to eq("lv")
        expect(page.at_css("#main-menu a[href='#{calls_path}']").text).to eq("Izsaukumi")
        expect(user.reload.locale).to be_nil
      end

      it "has a language button between the theme button and the account button, with the code of the language", :aggregate_failures do
        get calls_path

        buttons = page.css("header .header-bar > button.header-button").map { |button| button["popovertarget"] }
        expect(buttons.last(3)).to eq(%w[ theme-menu language-menu account-menu ])
        button = page.at_css("header button.language-button")
        expect([ button["type"], button.at_css("[aria-hidden=true]").text.strip, button.at_css(".visually-hidden").text.squish ])
          .to eq([ "button", "EN", "Language: English" ])
      end

      it "offers the languages in a menu without a script, each by its own name, the present one marked", :aggregate_failures do
        user.update!(locale: "ru")
        get root_path

        menu = page.at_css("header #language-menu[popover=auto][role=group]")
        forms = menu.css("form[action='#{language_path}']")
        expect(forms.map { |form| form.at_css("button").text.squish }).to eq(%w[ English Latviešu Русский ])
        expect(forms.map { |form| form.at_css("input[name=language]")["value"] }).to eq(%w[ en lv ru ])
        expect(forms.map { |form| form.at_css("button")["lang"] }).to eq(%w[ en lv ru ])
        expect(forms.map { |form| form.at_css("input[name=_method]")["value"] }.uniq).to eq(%w[ patch ])
        expect(forms.map { |form| form["data-turbo"] }.uniq).to eq(%w[ false ])
        expect(forms.map { |form| form.at_css("button")["aria-current"] }).to eq([ nil, nil, "true" ])
        expect(page.at_css("header button.language-button [aria-hidden=true]").text.strip).to eq("RU")
      end

      it "saves the choice with the user and comes back to the page it was made on, in the language", :aggregate_failures do
        patch language_path, params: { language: "lv" }, headers: { "HTTP_REFERER" => calls_url }

        expect(response).to have_http_status(:see_other)
        expect(response.location).to eq(calls_url)
        expect(user.reload.locale).to eq("lv")
        follow_redirect!
        expect(language).to eq("lv")
        expect(page.at_css("#main-menu a[href='#{calls_path}']").text).to eq("Izsaukumi")
      end

      it "puts the user's choice before what the browser asks for" do
        user.update!(locale: "lv")
        get root_path, headers: asking_for("ru")

        expect(language).to eq("lv")
      end

      it "comes back to the board when the page is not known, or is of another site", :aggregate_failures do
        patch language_path, params: { language: "lv" }
        expect(response).to redirect_to(root_path)

        patch language_path, params: { language: "ru" }, headers: { "HTTP_REFERER" => "https://elsewhere.example/calls" }
        expect(response).to redirect_to(root_path)
      end

      it "keeps the choice wherever the user signs in, and leaves other users theirs", :aggregate_failures do
        other = create(:user)
        patch language_path, params: { language: "ru" }
        delete session_path

        sign_in_as(user)
        get root_path
        expect(language).to eq("ru")
        delete session_path
        sign_in_as(other)
        get root_path
        expect(language).to eq("en")
      end

      it "refuses a language that is none of the system's, one sent as a list and none, and changes nothing", :aggregate_failures do
        user.update!(locale: "lv")

        [ { language: "de" }, { language: "zz" }, { language: [ "ru" ] }, { language: "" }, {} ].each do |sent|
          patch language_path, params: sent
          expect(response).to have_http_status(:unprocessable_content), sent.inspect
        end
        expect(user.reload.locale).to eq("lv")
      end

      it "changes nothing of the user but the language, whatever else is sent with it" do
        patch language_path, params: { language: "lv", role: "administrator", name: "Other Name", user: { role: "administrator" } }

        expect(user.reload.attributes.values_at("role", "name", "locale")).to eq([ "dispatcher", "Demo Dispatcher", "lv" ])
      end

      # A refusal by the rights is told after the action has been left.
      it "tells a refusal by the rights in the user's language" do
        user.update!(locale: "lv")
        get settings_path

        expect(flash[:alert]).to eq("Jūsu lomai nav atļauts")
      end

      it "leaves the language of one request behind when the next is served", :aggregate_failures do
        user.update!(locale: "ru")
        get root_path
        expect(language).to eq("ru")

        delete session_path
        get new_session_path
        expect(language).to eq("en")
      end
    end

    it "is the crew's too: the button on its screen, and the choice saved", :aggregate_failures do
      crew = create(:user, :crew)
      sign_in_as(crew)
      get crew_path
      expect(page.css("header .header-bar > button.header-button").map { |button| button["popovertarget"] })
        .to eq(%w[ theme-menu language-menu account-menu ])

      patch language_path, params: { language: "lv" }
      expect(response).to redirect_to(crew_path)
      expect(crew.reload.locale).to eq("lv")
      # Kept on its screen, the crew is told so in its language.
      post calls_path, params: { call: { kind: "alarm" } }
      expect(flash[:alert]).to eq("Jūsu lomai nav atļauts")
    end

    # 4.2: the API speaks to programs, in English, whoever's key it is.
    it "leaves the JSON API in English for a user of another language" do
      user.update!(locale: "ru")
      post api_v1_sites_path, params: { name: "" }, headers: { "Authorization" => "Bearer #{user.issue_api_key}" }, as: :json

      expect(response.parsed_body["errors"]["name"]).to include("Name can't be blank")
    end
  end
end
