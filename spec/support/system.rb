require "axe-rspec"
require "capybara/selenium/driver"
require "capybara/selenium/driver_specializations/chrome_driver"

# System tests run in headless Chrome at the size of a dispatcher's screen.
RSpec.configure do |config|
  config.before(:each, type: :system) do
    driven_by :selenium, using: :headless_chrome, screen_size: [ 1440, 900 ]
  end
end

module SystemHelpers
  # The session cookie the sign-in would set, set straight in the browser:
  # the sign-in form needs a solved ALTCHA task, and it has a test of its own.
  def sign_in_as(user)
    session = user.sessions.create!
    jar = ActionDispatch::TestRequest.create.cookie_jar
    jar.signed[:session_id] = session.id
    visit "/up"
    page.driver.browser.manage.add_cookie(name: "session_id", value: jar[:session_id])
  end

  # USR-09: a visitor's page follows the colour scheme of the browser.
  def prefer_colour_scheme(scheme)
    page.driver.browser.execute_cdp("Emulation.setEmulatedMedia",
                                    features: [ { name: "prefers-color-scheme", value: scheme } ])
  end
end

RSpec.configure do |config|
  config.include SystemHelpers, type: :system
end

# Capybara 3.40.0 ends every example by clearing the cookies of all origins
# with Storage.clearDataForOrigin and the origin "*", which Chrome 158 refuses
# as no valid URL. Its cookies are then cleared by Network.clearBrowserCookies;
# the application keeps nothing else in the browser.
module ChromeResetOfCookies
  def reset!
    super
  rescue Selenium::WebDriver::Error::InvalidArgumentError => error
    raise unless error.message.include?("* is not a valid URL")

    execute_cdp("Network.clearBrowserCookies")
  end
end

Capybara::Selenium::Driver::ChromeDriver.prepend(ChromeResetOfCookies)
