# STO-06: the nightly build of the map, done only when the map is due; a
# failure is raised so that it is recorded among the failed jobs.
class MapBuildJob < ApplicationJob
  queue_as :default

  def perform
    result = MapBuild.new.call(force: false)
    raise MapBuild::Failed, result.reason if result.failed?
  end
end
