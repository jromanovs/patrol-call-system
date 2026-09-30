require "rails_helper"
require "rake"

RSpec.describe "css:build", type: :task do
  it "compiles Sass, adds browser prefixes and minifies the result", :aggregate_failures do
    Rails.application.load_tasks if Rake::Task.tasks.empty?
    Rake::Task["css:build"].reenable
    Rake::Task["css:build"].invoke

    css = Rails.root.join("app/assets/builds/application.css").read
    expect(css).to include(".priority-label.priority-critical{")
    expect(css).to include("-webkit-text-size-adjust:100%")
    expect(css.lines.count).to be <= 2
  end
end
