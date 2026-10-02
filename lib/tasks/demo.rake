namespace :demo do
  desc "Load demo data on top of the seeds: bin/rails demo:load (prints the passwords of the users it creates)"
  task load: "db:seed" do
    puts DemoData.new.call
  end
end
