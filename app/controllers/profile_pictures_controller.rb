# USR-07: a user's own picture — a photo they send, their Gravatar, or none.
# The crew has it too.
class ProfilePicturesController < ApplicationController
  skip_before_action :keep_crew_on_its_screen
  # Each press makes the server wait for another service; a user's presses
  # must not hold it for everyone.
  rate_limit to: 10, within: 3.minutes, by: -> { Current.user.id }, store: ATTEMPTS, only: :gravatar,
             with: -> { tell(alert: "Try again later.") }
  before_action { @user = Current.user }

  def edit; end

  # Only a file no larger than a picture may be is read at all.
  def update
    file = params[:user][:avatar] if params[:user].is_a?(ActionController::Parameters)
    return tell(alert: "Choose a photo") unless file.is_a?(ActionDispatch::Http::UploadedFile)
    return tell(alert: User::PICTURE_REFUSAL) unless file.size <= User::PICTURE_LIMIT && @user.update(avatar: file)

    tell(notice: "Picture saved")
  end

  # The one moment the system turns to Gravatar: the user's own press.
  def gravatar
    case GravatarPicture.new(@user).take
    when :taken then tell(notice: "Picture taken from Gravatar")
    when :silent then tell(alert: "Gravatar did not answer. Try again later")
    else tell(alert: "Gravatar has no picture for your address")
    end
  end

  def destroy
    @user.avatar.purge
    tell(notice: "Picture removed")
  end

  private

  def tell(**message) = redirect_to(profile_path, status: :see_other, **message)
end
