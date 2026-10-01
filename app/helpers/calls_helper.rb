module CallsHelper
  # FLT-01: the choices of each select filter of the call list, in their order.
  def call_filter_options
    {
      status: enum_options(Call, :status),
      priority: enum_options(Call, :priority).reverse,
      kind: [ %w[ Alarm alarm ], [ "Client call", "client" ] ],
      district: enum_options(GuardedSite, :district),
      site_id: GuardedSite.order(:name).pluck(:name, :id),
      car_id: PatrolCar.order(:call_sign).pluck(:call_sign, :id)
    }
  end

  # DSP-02: whole minutes between two steps of the timeline, seconds dropped as
  # in the handling time, so the last step and the total agree.
  def minutes_between(later, earlier) = ((later - earlier) / 60).floor
end
