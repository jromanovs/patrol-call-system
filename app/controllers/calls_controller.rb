# Registering alarm calls (ADD-05); the active calls are shown on the board.
class CallsController < ApplicationController
  before_action :set_sites, only: %i[ new create ]

  def index; end

  def new
    @call = authorize AlarmCall.new
  end

  def create
    @call = authorize AlarmCall.new(call_params.merge(registered_by: Current.user))
    if @call.save
      redirect_to root_path, notice: "Alarm call registered"
    else
      render :new, status: :unprocessable_content
    end
  end

  private

  # BR-1: only a site with an active contract can receive a call.
  def set_sites
    @sites = GuardedSite.active.order(:name)
  end

  def call_params
    params.expect(alarm_call: %i[ guarded_site_id alarm_type sensor_zone received_at description ])
  end
end
