module Api
  module V1
    # API-01, API-02: the calls, with the filters and order of the call list
    # (FLT-01 … FLT-03, SRT-01).
    class CallsController < BaseController
      def index
        authorize Call
        filter = CallFilter.new(params.permit(*::CallsController::FILTERS))
        return invalid(filter) if filter.invalid?

        @calls = filter.results.includes(:registered_by, :dispatched_by)
      end

      def show
        @call = authorize Call.includes(:guarded_site, :patrol_car, :registered_by, :dispatched_by)
                              .find(params.expect(:id))
      end

      # API-03: an alarm or a client call, registered by the user of the key
      # (ADD-05, ADD-07); the boards refresh as after the form (API-08).
      def create
        kind = ::CallsController::KINDS.fetch(params[:kind], AlarmCall)
        @call = authorize kind.new(fields(kind).merge(params.permit(:guarded_site_id, :received_at))
                                               .merge(registered_by: Current.user))
        @call.save ? render(:show, status: :created) : invalid(@call)
      end

      # API-04: an active call only (BR-7).
      def update
        @call = authorize Call.find(params.expect(:id))
        @call.update(fields(@call.class)) ? render(:show) : invalid(@call)
      end

      # API-05: a finished call, by the supervisor or the administrator (BR-8, BR-14).
      def destroy
        call = authorize Call.find(params.expect(:id))
        call.destroy ? head(:no_content) : refuse(call.errors.full_messages.to_sentence)
      end

      private

      # The fields of the call form for an alarm or a client call.
      def fields(kind) = params.permit(*::CallsController::COMMON, *::CallsController::OWN.fetch(kind))
    end
  end
end
