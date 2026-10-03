# UPD-14 … UPD-16, CRW-12: the further cars of a call — the dialog of free
# cars and the sending, by the staff; the acceptance and the arrival, by the
# staff or by the crew of that car; the release, by the staff.
class BackupsController < CallStepsController
  skip_before_action :keep_crew_on_its_screen, only: %i[ accept arrive ]
  before_action :set_backup, only: %i[ accept arrive release ]

  def new
    steps.refuse_unserved
    # BR-22: the car that asked for help is never sent to its own call.
    @cars = PatrolCar.available.where.not(id: @call.raised_by_id)
                     .in_order_of(:district, [ @call.district ], filter: false).order(:call_sign)
  end

  def create
    car = PatrolCar.find(params.expect(:patrol_car_id))
    steps.send_car(car)
    redirect_to root_path, notice: "#{car.call_sign} sent to #{@call.place} as a further car"
  end

  def accept
    redirect_back_or_to home_path, notice: steps.accept(@backup)
  end

  def arrive
    redirect_back_or_to home_path, notice: steps.arrive(@backup, position: crew_position)
  end

  # The dispatcher stays where the step was recorded: the board or the call page.
  def release
    redirect_back_or_to call_path(@call), notice: steps.release(@backup)
  end

  private

  # The crew is granted only the acceptance and the arrival of its own car.
  def permission = action_name.in?(%w[ accept arrive ]) ? :back? : :update?

  def set_backup
    @backup = @call.backups.find(params.expect(:id))
    return unless Current.user.crew? && @backup.patrol_car_id != Current.user.patrol_car_id

    raise Pundit::NotAuthorizedError
  end

  def steps = BackupStep.new(@call, Current.user)
end
