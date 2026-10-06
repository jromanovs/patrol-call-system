# USR-10: a user chooses the language of the pages. The crew too. The choice
# is saved with the user, and the page it was made on is shown again.
class LanguagesController < ApplicationController
  skip_before_action :keep_crew_on_its_screen

  def update
    # A value that is no offered language, or no single value, is none.
    chosen = params[:language].to_s.presence_in(Language.offered)
    return head(:unprocessable_content) unless chosen && Current.user.update(locale: chosen)

    redirect_back_or_to home_path, status: :see_other
  end
end
