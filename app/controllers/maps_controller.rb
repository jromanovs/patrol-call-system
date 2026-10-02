class MapsController < ApplicationController
  # DSP-05: every site under an active contract; opened on the site asked for
  # from its page. Without a map file yet, the first build starts (STO-06).
  def show
    @map = MapBuild.new.current
    return MapBuildJob.perform_later if @map.nil?

    @markers = MapMarker.for(GuardedSite.active.includes(:address).order(:name, :id))
    @focus = @markers.find { |marker| marker.site.id.to_s == params[:site] }
  end
end
