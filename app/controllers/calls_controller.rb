# Registering alarm and client calls (ADD-05, ADD-07) and editing an active
# call (UPD-05); the active calls are shown on the board.
class CallsController < ApplicationController
  KINDS = { "alarm" => AlarmCall, "client" => ClientCall }.freeze
  COMMON = %i[ priority description ].freeze
  OWN = { AlarmCall => %i[ alarm_type sensor_zone ], ClientCall => %i[ caller_name caller_phone ] }.freeze

  before_action :set_sites, only: %i[ new create ]
  before_action :set_call, only: %i[ edit update ]

  def index; end

  def new
    @call = authorize AlarmCall.new
  end

  def create
    kind = KINDS.fetch(params.dig(:call, :kind), AlarmCall)
    fields = params.expect(call: [ :kind, :guarded_site_id, :received_at, *COMMON, *OWN.fetch(kind) ]).except(:kind)
    @call = authorize kind.new(fields.merge(registered_by: Current.user))
    if @call.save
      redirect_to root_path, notice: "#{@call.model_name.human} registered"
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit; end

  def update
    if @call.update(params.expect(call: [ *COMMON, *OWN.fetch(@call.class) ]))
      redirect_to root_path, notice: "Call updated"
    else
      render :edit, status: :unprocessable_content
    end
  end

  private

  # BR-1: only a site with an active contract can receive a call.
  def set_sites
    @sites = GuardedSite.active.order(:name)
  end

  def set_call
    @call = authorize Call.find(params.expect(:id))
  end
end
