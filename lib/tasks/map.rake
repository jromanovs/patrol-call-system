namespace :map do
  desc "Build the map of Latvia now, whatever the age of the current one: bin/rails map:build"
  task build: :environment do
    result = MapBuild.new.call(force: true)
    abort "Map not built: #{result.reason || result.status}" unless result.status == :built

    puts "Map built: #{result.file}"
  end
end
