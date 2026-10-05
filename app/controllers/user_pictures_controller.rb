# USR-07: a user's picture, sent to signed-in users only and by no address
# of the storage itself. A crew's own header shows its picture.
class UserPicturesController < ApplicationController
  skip_before_action :keep_crew_on_its_screen

  def show
    picture = User.find(params.expect(:id)).avatar
    return head(:not_found) unless picture.attached?

    expires_in 1.day, private: true
    send_data picture.download, type: picture.content_type, disposition: "inline"
  rescue ActiveStorage::FileNotFoundError
    head :not_found
  end
end
