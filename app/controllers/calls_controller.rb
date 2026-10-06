# Registering alarm and client calls (ADD-05, ADD-07) and editing an active
# call (UPD-05); the active calls are shown on the board.
class CallsController < ApplicationController
  KINDS = { "alarm" => AlarmCall, "client" => ClientCall }.freeze
  COMMON = %i[ priority description ].freeze
  # A crew's SOS has no fields of its own to edit (BR-21).
  OWN = { AlarmCall => %i[ alarm_type sensor_zone ], ClientCall => %i[ caller_name caller_phone ], SosCall => [] }.freeze

  FILTERS = %i[ q status priority kind district site_id car_id from to sort direction ].freeze

  before_action :set_sites, only: %i[ new create ]
  before_action :set_call, only: %i[ show edit update destroy ]

  # FLT-01 … FLT-03, SRT-01, DYN-06
  def index
    authorize Call
    @filter = CallFilter.new(params.permit(*FILTERS))
    @filter.validate
    @calls = @filter.results
  end

  # DSP-02
  def show; end

  def new
    @call = authorize AlarmCall.new
  end

  def create
    kind = KINDS.fetch(params.dig(:call, :kind), AlarmCall)
    fields = params.expect(call: [ :kind, :guarded_site_id, :received_at, *COMMON, *OWN.fetch(kind) ]).except(:kind)
    @call = authorize kind.new(fields.merge(registered_by: Current.user))
    if @call.save
      redirect_to root_path, notice: t(".registered.#{@call.model_name.i18n_key}")
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit; end

  def update
    if @call.update(params.expect(call: [ *COMMON, *OWN.fetch(@call.class) ]))
      redirect_to root_path, notice: t(".updated")
    else
      render :edit, status: :unprocessable_content
    end
  end

  # DEL-05, DEL-06
  def destroy
    if @call.destroy
      redirect_to calls_path, notice: t(".deleted"), status: :see_other
    else
      redirect_to call_path(@call), alert: @call.errors.full_messages.to_sentence, status: :see_other
    end
  end

  private

  def default_sort = "received_at"
  helper_method :default_sort

  def default_direction = "desc"

  # BR-1: only a site with an active contract can receive a call.
  def set_sites
    @sites = GuardedSite.active.order(:name)
  end

  def set_call
    @call = authorize Call.find(params.expect(:id))
  end
end
