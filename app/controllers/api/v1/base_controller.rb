module Api
  module V1
    # 4.2: JSON in and out. The user comes from the personal API key in the
    # Authorization header (BR-13, USR-04), never from a browser session, so
    # no form token is needed; the rights are those of the pages (BR-14).
    class BaseController < ActionController::API
      include ActionController::HttpAuthentication::Token::ControllerMethods
      include Pundit::Authorization

      before_action :authenticate
      # Every action decides on the rights, or says that it needs none.
      after_action :verify_authorized

      rescue_from(ActiveRecord::RecordNotFound) { render json: { error: "Not found" }, status: :not_found }
      rescue_from(Pundit::NotAuthorizedError) { render json: { error: "Not allowed for your role" }, status: :forbidden }

      private

      def authenticate
        Current.api_user = authenticate_with_http_token { |key, _options| User.find_by_api_key(key) }
        return if Current.api_user

        headers["WWW-Authenticate"] = 'Bearer realm="patrol-call-system"'
        render json: { error: "Send the API key of an active user: Authorization: Bearer <key>" }, status: :unauthorized
      end

      def pundit_user = Current.user

      def invalid(record)
        render json: { errors: record.errors.to_hash(true).transform_keys(&:to_s) }, status: :unprocessable_content
      end
    end
  end
end
