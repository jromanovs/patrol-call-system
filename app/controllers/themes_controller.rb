# USR-09: a user chooses how the pages look. The crew too. The choice is
# saved with the user, and the page it was made on is shown again.
class ThemesController < ApplicationController
  skip_before_action :keep_crew_on_its_screen

  def update
    # A value that is none of the themes, or no single value, is none.
    chosen = params[:theme].to_s.presence_in(User.themes.keys)
    return head(:unprocessable_content) unless Current.user.update(theme: chosen)

    redirect_back_or_to home_path, status: :see_other
  end
end
