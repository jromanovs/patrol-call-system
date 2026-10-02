# DSP-05: the map is the main screen's; the old address leads there.
class MapsController < ApplicationController
  def show
    redirect_to root_path(site: params[:site].presence)
  end
end
