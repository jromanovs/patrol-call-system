# USR-06: a user changes their own password. Not for the crew, which is kept
# on its screen: its password is the administrator's to change.
class PasswordsController < ApplicationController
  COUNTS = ActiveSupport::Cache::MemoryStore.new

  # BR-16: as at sign-in, a guess at the current password is not tried
  # without end.
  rate_limit to: 10, within: 3.minutes, by: -> { Current.user.id }, store: COUNTS, only: :update,
             with: -> { redirect_to edit_password_path, alert: "Try again later.", status: :see_other }
  before_action { @user = Current.user }

  def edit; end

  def update
    return render(:edit, status: :unprocessable_content) unless @user.change_password(**typed)

    # Whoever knew the former password is signed out; this session stays.
    @user.sessions.where.not(id: Current.session).destroy_all
    redirect_to profile_path, notice: "Password changed. Other devices are signed out", status: :see_other
  end

  private

  def typed
    sent = params.fetch(:user, {}).permit(:password_challenge, :password, :password_confirmation)
    { current: sent[:password_challenge], password: sent[:password], confirmation: sent[:password_confirmation] }
  end
end
