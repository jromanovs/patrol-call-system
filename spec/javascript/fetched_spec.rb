require "rails_helper"

# The examples of this folder give a script the text of the scripts it
# fetches. In the browser a line that fetches a script that is not there, or
# a name the script does not give, stops the fetching script altogether.
RSpec.describe "FetchedScripts" do
  def given(script)
    text = script.exist? ? script.read : ""
    text.scan(/^export (?:function|const) (\w+)/).flatten + text.scan(/^export \{ (.+) \}$/).flatten.flat_map { |names| names.split(", ") }
  end

  it "are there, and give every name asked of them", :aggregate_failures do
    folder = Rails.root.join("app/javascript/controllers")
    asked = folder.glob("*.js").flat_map { |script| script.read.scan(/^import \{ (.+) \} from "controllers\/(\w+)"$/) }

    expect(asked).to include([ "verdict", "field_fault" ], [ "settle", "fresh_mark" ])
    asked.each do |names, script|
      expect(given(folder.join("#{script}.js"))).to include(*names.split(", ")), "#{script} is asked for #{names}"
    end
  end
end
