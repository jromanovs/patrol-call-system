# USR-06: a user changes their own password. Not for the crew, which is kept
# on its screen: its password is the administrator's to change.
class PasswordsController < ApplicationController
  # BR-16: as at sign-in, a guess at the current password is not tried
  # without end.
  rate_limit to: 10, within: 3.minutes, by: -> { Current.user.id }, store: ATTEMPTS, only: :update,
             with: -> { redirect_to edit_password_path, alert: "Try again later.", status: :see_other }
  before_action { @user = Current.user }

  def edit; end

  def update
    return render(:edit, status: :unprocessable_content) unless @user.change_password(**typed)

    told = "Password changed. Other devices are signed out"
    told += ", and the API key is void" if @user.saved_change_to_api_key_digest?
    redirect_to profile_path, notice: told, status: :see_other
  end

  private

  # Fields sent as one value or as a list are no fields: the change is then
  # refused as one with nothing typed.
  def typed
    sent = params[:user].is_a?(ActionController::Parameters) ? params[:user] : ActionController::Parameters.new
    sent = sent.permit(:password_challenge, :password, :password_confirmation)
    { current: sent[:password_challenge], password: sent[:password], confirmation: sent[:password_confirmation] }
  end
end
