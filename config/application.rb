require_relative "boot"

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "active_storage/engine"
require "action_controller/railtie"
# require "action_mailer/railtie"
# require "action_mailbox/engine"
# require "action_text/engine"
require "action_view/railtie"
require "action_cable/engine"
# require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module PatrolCallSystem
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.eager_load_paths << Rails.root.join("extras")

    # BR-10: times are shown in Riga local time; the database keeps UTC.
    config.time_zone = "Riga"

    # USR-10: the languages of the system; English is the one every text
    # exists in. Only these are loaded from the standard texts of Rails.
    config.i18n.available_locales = %i[ en lv ru ]
    config.i18n.default_locale = :en

    # CRW-10, USR-07: the crew's photos and the users' pictures are kept by
    # Active Storage on the server's disk. Only the app's own controllers
    # send one, a photo to a signed-in user allowed to see its call and a
    # picture to any signed-in user (BR-13), so Active Storage draws no
    # routes of its own; the browser reduces each before sending, and the
    # server has no image library, so nothing is analysed.
    config.active_storage.draw_routes = false
    config.active_storage.analyzers = []

    # Don't generate system test files.
    config.generators.system_tests = nil
  end
end
