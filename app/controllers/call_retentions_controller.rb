# DEL-09: for how many months calls are kept before they can be deleted. A
# shorter period deletes nothing by itself, so it asks nothing (BR-23).
class CallRetentionsController < ApplicationController
  before_action { authorize :setting, :update? }

  def update
    setting = Setting.current
    told = if setting.update(call_months: params[:months])
      { notice: "Calls are kept for #{setting.call_months} months" }
    else
      { alert: setting.errors.full_messages.to_sentence }
    end
    redirect_to new_call_cleanup_path, status: :see_other, **told
  end
end
