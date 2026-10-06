class ApplicationController < ActionController::Base
  include Authentication
  include Pundit::Authorization

  # BR-16: where the attempts of a user are counted — in the cache all server
  # processes share, as those of sign-in are. Where that cache keeps nothing,
  # as in the tests, the process keeps the count itself.
  ATTEMPTS = Rails.cache.is_a?(ActiveSupport::Cache::NullStore) ? ActiveSupport::Cache::MemoryStore.new : Rails.cache

  # USR-10: every page in the language of its user. Before the checks that
  # answer with words of their own.
  around_action :in_language

  # CRW-03: a crew user works on its screen and its steps only; a controller
  # the crew may use says so by skipping this.
  before_action :keep_crew_on_its_screen

  # A script asking for JSON gets the refusal itself, not a page to follow.
  # The refusal is told after the action has been left, so the language is
  # set once more.
  rescue_from Pundit::NotAuthorizedError do
    in_language do
      if request.format.json? then render json: { error: t("common.not_allowed") }, status: :forbidden
      else redirect_back_or_to home_path, alert: t("common.not_allowed")
      end
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

  def in_language(&) = I18n.with_locale(page_language, &)

  # The language the user chose while it is offered; else the offered
  # language the browser asks for first; else English.
  def page_language
    chosen = Current.user&.locale
    return chosen if Language.offered.include?(chosen)

    Language.asked(request.headers["Accept-Language"]) || I18n.default_locale
  end

  def keep_crew_on_its_screen
    return unless Current.user&.crew?

    if request.get? || request.head? then redirect_to crew_path
    else redirect_to crew_path, alert: t("common.not_allowed"), status: :see_other
    end
  end

  # Where a user works: the board, or the crew screen for a crew user.
  def home_path = Current.user&.crew? ? crew_path : root_path

  # The direction a list is shown in before a header is clicked (SRT-*).
  def default_direction = "asc"
  helper_method :default_direction
end
