class MapsController < ApplicationController
  # DSP-05: every site under an active contract; opened on the site asked for
  # from its page. Without a map file yet, the first build starts (STO-06).
  def show
    build = MapBuild.new
    @map = build.current
    return start_first_build(build) if @map.nil?

    @markers = MapMarker.for(GuardedSite.active.includes(:address).order(:name, :id))
    @focus = @markers.find { |marker| marker.site.id.to_s == params[:site] }
  end

  private

  # At most once an hour, so visits never repeat a failed download.
  def start_first_build(build)
    MapBuildJob.perform_later unless build.attempted_since?(1.hour.ago)
  end
end
