# DEL-07, DEL-08, DYN-08: the supervisor deletes old finished calls after a
# preview of how many match (BR-14).
class CallCleanupsController < ApplicationController
  before_action { authorize Call, :destroy? }

  # The first visit offers both statuses and no messages yet.
  def new
    @setting = Setting.current
    if request.query_parameters.any?
      @cleanup = CallCleanup.new(criteria)
      @cleanup.validate
    else
      @cleanup = CallCleanup.new(statuses: CallCleanup::FINISHED)
    end
  end

  def create
    redirect_to new_call_cleanup_path(criteria), status: :see_other, **result(CallCleanup.new(criteria))
  end

  private

  def criteria = params.permit(:before, :kind, :outcome, statuses: []).to_h.compact_blank

  def result(cleanup)
    return { alert: cleanup.errors.full_messages.to_sentence } if cleanup.invalid?

    deleted = cleanup.delete(params[:match].to_s)
    deleted.zero? ? { alert: "No calls match" } : { notice: "#{helpers.pluralize(deleted, 'call')} deleted" }
  rescue CallCleanup::Changed => change
    { alert: "The matching calls changed since the preview: #{change.message}. Nothing was deleted" }
  end
end
