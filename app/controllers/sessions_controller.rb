class SessionsController < ApplicationController
  include CaptchaVerification

  allow_unauthenticated_access only: %i[ new create ]
  skip_before_action :keep_crew_on_its_screen
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to new_session_path, alert: t("common.try_later") }

  def new
  end

  def create
    return redirect_to new_session_path, alert: t(".unverified") unless verify_altcha

    user = User.authenticate_by(params.permit(:email_address, :password))
    if user&.active?
      user.update!(last_signed_in_at: Time.current)
      start_new_session_for user
      redirect_to after_authentication_url
    else
      redirect_to new_session_path, alert: t(".refused")
    end
  end

  def destroy
    terminate_session
    redirect_to new_session_path, status: :see_other
  end
end
