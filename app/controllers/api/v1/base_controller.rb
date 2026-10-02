module Api
  module V1
    # 4.2: JSON in and out. The user comes from the personal API key in the
    # Authorization header (BR-13, USR-04), never from a browser session, so
    # no form token is needed; the rights are those of the pages (BR-14).
    class BaseController < ActionController::API
      include ActionController::HttpAuthentication::Token::ControllerMethods
      include Pundit::Authorization

      # The fields of a record come at the top level of the JSON body.
      wrap_parameters false

      before_action :authenticate
      before_action :keep_crew_to_its_steps
      # Every action decides on the rights, or says that it needs none.
      after_action :verify_authorized

      rescue_from(ActiveRecord::RecordNotFound) { render json: { error: "Not found" }, status: :not_found }
      rescue_from(Pundit::NotAuthorizedError) do
        render json: { error: "Not allowed for your role" }, status: :forbidden
      end
      rescue_from(ActionController::ParameterMissing) do |missing|
        render json: { error: "Missing field: #{missing.param}" }, status: :bad_request
      end
      rescue_from(ActionDispatch::Http::Parameters::ParseError) do
        render json: { error: "The request body is not valid JSON" }, status: :bad_request
      end

      private

      def authenticate
        Current.api_user = authenticate_with_http_token { |key, _options| User.find_by_api_key(key) }
        return if Current.api_user

        headers["WWW-Authenticate"] = 'Bearer realm="patrol-call-system"'
        render json: { error: "Send the API key of an active user: Authorization: Bearer <key>" }, status: :unauthorized
      end

      def pundit_user = Current.user

      # CRW-03: through the API the crew may only record its own car's
      # arrival and closing (the policy checks the car).
      def keep_crew_to_its_steps
        return unless Current.user&.crew?
        return if controller_name == "call_steps" && action_name.in?(%w[ arrive close ])

        render json: { error: "Not allowed for your role" }, status: :forbidden
      end

      # The fields and messages of the forms (FormsHelper#error_field): an
      # error of an association belongs to its id field. A filter has no
      # associations.
      def invalid(record)
        fields = record.errors.group_by do |error|
          record.class.try(:reflect_on_association, error.attribute)&.foreign_key || error.attribute.to_s
        end
        render json: { errors: fields.transform_values { |errors| errors.map(&:full_message) } },
               status: :unprocessable_content
      end

      # A refused deletion or step, with the reason (API-05, API-06).
      def refuse(reason) = render(json: { error: reason }, status: :unprocessable_content)
    end
  end
end
