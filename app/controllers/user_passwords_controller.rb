# USR-08: an administrator sets a new password for a user, in a dialog of
# its own, so that saving the user's form cannot change one by accident.
class UserPasswordsController < ApplicationController
  before_action :set_user
  # There the current password is asked for; here it is not.
  before_action -> { redirect_to profile_path, alert: "Change your own password on your profile", status: :see_other },
                if: -> { @user == Current.user }

  def edit; end

  def update
    return refuse unless @user.set_password(**typed)

    told = "Password of #{@user.name} changed; the user is signed out on every device"
    told += ", and the API key is void" if @user.saved_change_to_api_key_digest?
    redirect_to edit_user_path(@user), notice: told, status: :see_other
  end

  private

  def set_user
    @user = authorize User.find(params.expect(:user_id)), :update?
  end

  # Fields sent as one value or as a list are no fields.
  def typed
    sent = params[:user].is_a?(ActionController::Parameters) ? params[:user] : ActionController::Parameters.new
    sent = sent.permit(:password, :password_confirmation)
    { password: sent[:password], confirmation: sent[:password_confirmation] }
  end

  # On the open page the refusal goes back into the dialog frame. Asked for
  # as a page, it is the dialog alone, as the other dialogs are.
  def refuse
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace("modal", template: "user_passwords/edit"), status: :unprocessable_content
      end
      format.html { render :edit, status: :unprocessable_content }
    end
  end
end
