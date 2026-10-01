namespace :addresses do
  desc "Load the addresses of a city from the State Address Register: bin/rails addresses:load FILE=aw_eka.csv [CITY=Rīga]"
  task load: :environment do
    file = ENV.fetch("FILE") { abort "Give the register file: FILE=aw_eka.csv" }
    puts AddressRegisterLoad.new(file, city: ENV.fetch("CITY", "Rīga")).call
  rescue AddressRegisterLoad::MissingColumns => error
    abort error.message
  end
end
