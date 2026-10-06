require "rails_helper"

RSpec.describe "The words of what a page is built with follow its language (USR-10)" do
  include_context "without the seeded records"

  def asking_for(languages) = { "HTTP_ACCEPT_LANGUAGE" => languages }

  # Latvian is given here by hand, with a word of each of these places.
  before do
    I18n.backend.translations(do_init: true)
    I18n.backend.store_translations(:lv, language: { name: "Latviešu" },
                                         sessions: { new: { captcha: { label: "Es neesmu robots" } } },
                                         maps: { view: { zoom_in: "Tuvināt" } },
                                         pwa: { manifest: { description: "Patruļas automašīnu izsaukumi" } })
    allow(MapBuild).to receive(:new).and_return(instance_double(MapBuild, current: "demo.pmtiles", attempted_since?: true))
  end

  after { I18n.backend.reload! }

  describe "the check of the sign-in page" do
    # The words the library shows when it is given none, as its file has them.
    let(:own) do
      list = Rails.root.join("vendor/javascript/altcha.js").read[/\{[^{}]*label:"I'm not a robot"[^{}]*\}/]
      list.scan(/(\w+):(?:"((?:[^"\\]|\\.)*)"|'((?:[^'\\]|\\.)*)')/).to_h { |name, double, single| [ name, double || single ] }
    end

    def given(asking = nil)
      get new_session_path, headers: asking_for(asking)
      JSON.parse(response.parsed_body.at_css("altcha-widget")["strings"])
    end

    it "is given every word the library shows, in English as the library words them", :aggregate_failures do
      expect(own.size).to eq(17)
      expect(given).to eq(own)
    end

    it "is given its words in the language of the page" do
      expect(given("lv")).to include("label" => "Es neesmu robots")
    end
  end

  describe "the map" do
    def given(asking = nil)
      get root_path, headers: asking_for(asking)
      view = response.parsed_body.at_css(".map-view")
      %w[ zoom-in zoom-out attribution title marker close ].to_h { |word| [ word, view["data-map-#{word}-text-value"] ] }
    end

    before { sign_in_as(create(:user)) }

    it "is given the words of its buttons, of a mark and of the details of a mark, in English as the library words them" do
      expect(given).to eq("zoom-in" => "Zoom in", "zoom-out" => "Zoom out", "attribution" => "Toggle attribution", "title" => "Map",
                          "marker" => "Map marker", "close" => "Close popup")
    end

    it "is given its words in the language of the page" do
      expect(given("lv")).to include("zoom-in" => "Tuvināt")
    end

    it "hands every one of them to the library by the name the library knows it by" do
      script = Rails.root.join("app/javascript/controllers/map_controller.js").read

      expect(script.scan(/"((?:NavigationControl|AttributionControl|Map|Marker|Popup)\.\w+)": this\.(\w+)TextValue/))
        .to contain_exactly(%w[ NavigationControl.ZoomIn zoomIn ], %w[ NavigationControl.ZoomOut zoomOut ],
                            %w[ AttributionControl.ToggleAttribution attribution ], %w[ Map.Title title ],
                            %w[ Marker.Title marker ], %w[ Popup.Close close ])
    end
  end

  describe "the description of the application for a phone that installs it (CRW-01)" do
    def described(asking = nil)
      get pwa_manifest_path(format: :json), headers: asking_for(asking)
      response.parsed_body["description"]
    end

    it "is in the offered language the browser asks for first, and in English otherwise", :aggregate_failures do
      expect(described("lv,en;q=0.5")).to eq("Patruļas automašīnu izsaukumi")
      expect(described("de")).to eq("The calls of the patrol cars, and the crew's own call.")
      expect(described).to eq("The calls of the patrol cars, and the crew's own call.")
    end
  end
end
