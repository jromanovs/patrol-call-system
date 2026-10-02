class ApplicationController < ActionController::Base
  include Authentication
  include Pundit::Authorization

  # CRW-03: a crew user works on its screen and its steps only; a controller
  # the crew may use says so by skipping this.
  before_action :keep_crew_on_its_screen

  # A script asking for JSON gets the refusal itself, not a page to follow.
  rescue_from Pundit::NotAuthorizedError do
    if request.format.json? then render json: { error: "Not allowed for your role" }, status: :forbidden
    else redirect_back_or_to home_path, alert: "Not allowed for your role"
    end
  end

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  private

  def pundit_user
    Current.user
  end

  def keep_crew_on_its_screen
    return unless Current.user&.crew?

    if request.get? || request.head? then redirect_to crew_path
    else redirect_to crew_path, alert: "Not allowed for your role", status: :see_other
    end
  end

  # Where a user works: the board, or the crew screen for a crew user.
  def home_path = Current.user&.crew? ? crew_path : root_path

  # The direction a list is shown in before a header is clicked (SRT-*).
  def default_direction = "asc"
  helper_method :default_direction
end
