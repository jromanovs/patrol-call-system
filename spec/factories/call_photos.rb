FactoryBot.define do
  factory :call_photo do
    call factory: :alarm_call
    user factory: %i[ user crew ]
    image { Rack::Test::UploadedFile.new(Rails.root.join("spec/fixtures/files/photo.jpg"), "image/jpeg") }
  end
end
