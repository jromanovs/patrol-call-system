# USR-05: a signed-in user's own page. The crew has one too.
class ProfilesController < ApplicationController
  skip_before_action :keep_crew_on_its_screen

  def show; end
end
