module Api
  module V1
    # API-09: addresses of the register, as the suggestions of the site form
    # (FLT-07); every signed-in user may read the register (BR-14).
    class AddressesController < BaseController
      def index
        skip_authorization
        text = params[:q].to_s
        if text.strip.length < 3
          return render json: { errors: { q: [ "Enter at least 3 characters" ] } }, status: :unprocessable_content
        end

        @addresses = Address.search(text)
      end
    end
  end
end
