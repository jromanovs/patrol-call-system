# USR-07: a user's own picture — a photo they send, their Gravatar, or none.
# The crew has it too.
class ProfilePicturesController < ApplicationController
  skip_before_action :keep_crew_on_its_screen
  # Each press makes the server wait for another service; a user's presses
  # must not hold it for everyone.
  rate_limit to: 10, within: 3.minutes, by: -> { Current.user.id }, store: ATTEMPTS, only: :gravatar,
             with: -> { tell(alert: t("common.try_later")) }
  before_action { @user = Current.user }

  def edit; end

  # Only a file no larger than a picture may be is read at all.
  def update
    file = params[:user][:avatar] if params[:user].is_a?(ActionController::Parameters)
    return tell(alert: t(".no_photo")) unless file.is_a?(ActionDispatch::Http::UploadedFile)
    return tell(alert: User.picture_refusal) unless file.size <= User::PICTURE_LIMIT && @user.update(avatar: file)

    tell(notice: t(".saved"))
  end

  # The one moment the system turns to Gravatar: the user's own press.
  def gravatar
    case GravatarPicture.new(@user).take
    when :taken then tell(notice: t(".taken"))
    when :silent then tell(alert: t(".silent"))
    when :busy then tell(alert: t("common.try_later"))
    else tell(alert: t(".none"))
    end
  end

  def destroy
    @user.avatar.purge
    tell(notice: t(".removed"))
  end

  private

  def tell(**message) = redirect_to(profile_path, status: :see_other, **message)
end
