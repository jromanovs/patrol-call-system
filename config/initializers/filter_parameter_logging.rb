# Be sure to restart your server when you modify this file.

# Configure parameters to be partially matched (e.g. passw matches password) and filtered from the log file.
# Use this to limit dissemination of sensitive information.
# See the ActiveSupport::ParameterFilter documentation for supported notations and behaviors.
Rails.application.config.filter_parameters += [
  :passw, :email, :secret, :token, :_key, :crypt, :salt, :certificate, :otp, :ssn, :cvv, :cvc,
  # BR-20: the receiver of Traccar Client knows a car by its identifier alone,
  # sent as `id`. Everywhere else `id` is the number of a record and stays.
  lambda do |key, value, parameters|
    value.replace("[FILTERED]") if key == "id" && value.is_a?(String) && parameters["controller"] == "traccar"
  end
]
