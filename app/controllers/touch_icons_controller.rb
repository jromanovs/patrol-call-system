# CRW-01: the Home Screen icon under the names an iPhone asks for when the
# app is added from a browser other than Safari, which then reads no link of
# the page. Open to everyone like the manifest, and kept a day only, so that
# a new picture reaches the phones that add the app later.
class TouchIconsController < ActionController::Base
  def show
    expires_in 1.day, public: true
    send_file Rails.root.join("app/assets/images/icon.png"), type: "image/png", disposition: "inline"
  end
end
