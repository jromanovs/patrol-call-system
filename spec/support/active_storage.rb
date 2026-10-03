# CRW-10: the files the tests store are removed once they have run.
RSpec.configure do |config|
  config.after(:suite) { FileUtils.rm_rf(ActiveStorage::Blob.service.root) }
end
