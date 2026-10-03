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

      def accept
        step.accept
        answer
      end

      def arrive
        step.arrive(position: crew_position)
        answer
      end

      def close
        step.close(params[:outcome], params[:note], position: crew_position)
        answer
      end

      def cancel
        step.cancel(params[:reason])
        answer
      end

      private

      # CRW-03: the crew is granted only its own acceptance, arrival and closing.
      PERMISSIONS = { "accept" => :accept?, "arrive" => :arrive?, "close" => :close? }.freeze

      def set_call
        @call = authorize Call.find(params.expect(:id)), PERMISSIONS.fetch(action_name, :update?)
      end

      def step = CallStep.new(@call, Current.user)

      # CRW-07: the crew may send where its phone is; the staff's steps keep
      # no position.
      def crew_position
        params.slice(:latitude, :longitude, :accuracy).permit(:latitude, :longitude, :accuracy).to_h.symbolize_keys if Current.user.crew?
      end

      def answer = render("api/v1/calls/show")
    end
  end
end
