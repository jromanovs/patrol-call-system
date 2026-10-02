module Api
  module V1
    # API-06: the steps of a call, by the rules of the board (UPD-06 …
    # UPD-11); 409 when the car is not available, 422 for any other refusal.
    # The boards refresh as after a step on the board (API-08).
    class CallStepsController < BaseController
      before_action :set_call

      # Rails tries the handler declared last first, so the narrower one comes last.
      rescue_from(CallStep::Refused) { |refusal| refuse(refusal.message) }
      rescue_from(CallStep::Unavailable) { |refusal| render json: { error: refusal.message }, status: :conflict }

      def send_car
        step.dispatch(PatrolCar.find(params.expect(:patrol_car_id)))
        answer
      end

      def arrive
        step.arrive
        answer
      end

      def close
        step.close(params[:outcome], params[:note])
        answer
      end

      def cancel
        step.cancel(params[:reason])
        answer
      end

      private

      def set_call
        @call = authorize Call.find(params.expect(:id)), :update?
      end

      def step = CallStep.new(@call, Current.user)

      def answer = render("api/v1/calls/show")
    end
  end
end
