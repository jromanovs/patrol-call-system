# CRW-10, BR-19: the crew's photos of a call, added from its phone on site and
# sent only to a signed-in user allowed to see the call.
class CallPhotosController < ApplicationController
  skip_before_action :keep_crew_on_its_screen

  def show
    call = authorize Call.find(params.expect(:call_id)), :see_photos?
    photo = call.photos.find(params.expect(:id))
    expires_in 1.day, private: true
    send_data photo.image.download, type: photo.image.content_type, disposition: "inline",
                                    filename: "call-#{call.id}-photo-#{photo.id}#{File.extname(photo.image.filename.to_s)}"
  end

  # A choice of photos is kept whole or not at all.
  def create
    @call = authorize Call.find(params.expect(:call_id)), :add_photo?
    files = Array(params[:photos]).compact_blank
    return refuse("Choose a photo") if files.empty?

    CallPhoto.transaction { files.each { |file| @call.photos.create!(user: Current.user, image: file) } }
    redirect_to from_closing? ? new_call_closing_path(@call) : crew_path, status: :see_other
  rescue ActiveRecord::RecordInvalid
    refuse(CallPhoto::REFUSAL)
  end

  private

  def from_closing? = params[:from] == "closing"

  # From the closing dialog the dialog stays open and says why; from the
  # crew screen the screen says it.
  def refuse(message)
    return redirect_to(crew_path, alert: message, status: :see_other) unless from_closing?

    @refusal = message
    render "closings/new", status: :unprocessable_content
  end
end
