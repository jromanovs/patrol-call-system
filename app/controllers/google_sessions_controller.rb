# Sign-in with Google: only an existing active user whose e-mail address
# equals the address Google has verified. The first sign-in links the Google
# account; afterwards only that account signs the user in, until the address
# of the user changes (BR-15).
class GoogleSessionsController < ApplicationController
  allow_unauthenticated_access
  skip_before_action :keep_crew_on_its_screen

  def create
    user = linked_user(request.env["omniauth.auth"])
    return redirect_to new_session_path, alert: t(".refused") unless user

    user.update!(google_uid: user.google_uid || auth_uid, last_signed_in_at: Time.current)
    start_new_session_for user
    redirect_to after_authentication_url
  end

  def failure
    redirect_to new_session_path, alert: t(".failed")
  end

  private

  def linked_user(auth)
    return unless auth&.dig("extra", "raw_info", "email_verified")

    user = User.find_by(email_address: auth.dig("info", "email").to_s.strip.downcase, active: true)
    user if user && [ nil, auth["uid"] ].include?(user.google_uid)
  end

  def auth_uid
    request.env["omniauth.auth"]["uid"]
  end
end
