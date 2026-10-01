# Sign-in with Google. The client comes from the encrypted credentials
# (google: client_id, client_secret); without them the provider is not
# registered and the sign-in page shows no Google button. Specs use the
# OmniAuth test mode, which needs no client.
google = Rails.application.credentials.google || {}
Rails.configuration.x.google_sign_in = google[:client_id].present? || Rails.env.test?

if Rails.configuration.x.google_sign_in
  Rails.application.config.middleware.use OmniAuth::Builder do
    provider :google_oauth2, google[:client_id], google[:client_secret], scope: "email", prompt: "select_account"
  end
end

OmniAuth.config.logger = Rails.logger
