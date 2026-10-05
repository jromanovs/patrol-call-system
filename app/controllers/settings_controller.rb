# TRK-05, DEL-09: what the administrator sets for the whole system — for how
# long car positions and calls are kept.
class SettingsController < ApplicationController
  before_action -> { authorize :setting, action_name == "show" ? :show? : :update? }
  before_action :load_page
  helper_method :in_force

  def show; end

  # TRK-05: a shorter period deletes what a longer one kept, so it is saved
  # only after the question about it is answered.
  def keep_positions
    @setting.position_months = params[:position_months]
    return refuse unless @setting.valid?
    return ask_about_shorter if @setting.shorter?(params[:position_months]) && params[:shorter] != "yes"

    @setting.save!
    told = "Car positions are kept for #{@setting.position_months} months"
    redirect_to settings_path, notice: told, status: :see_other
  end

  # DEL-09: a shorter period deletes nothing by itself, so it asks nothing
  # (BR-23).
  def keep_calls
    @setting.call_months = params[:call_months]
    return refuse unless @setting.valid?

    @setting.save!
    redirect_to settings_path, notice: "Calls are kept for #{@setting.call_months} months", status: :see_other
  end

  private

  def load_page
    @setting = Setting.current
    @oldest = CarPosition.kept_since
  end

  # What the page says is kept comes from the saved settings, also while
  # @setting holds a period that was refused.
  def in_force = @setting.changed? ? Setting.current : @setting

  # The page again, with the refusal beside the field it is about.
  def refuse = render(:show, status: :unprocessable_content)

  # On the open page the question goes into the dialog frame. Asked for as a
  # page, it is the dialog alone, as the other dialogs are.
  def ask_about_shorter
    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.replace("modal", template: "settings/shorter") }
      format.html { render :shorter, status: :unprocessable_content }
    end
  end
end
