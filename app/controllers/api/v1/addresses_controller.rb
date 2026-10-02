module Api
  module V1
    # API-09: addresses of the register, as the suggestions of the site form
    # (FLT-07); every signed-in user may read the register (BR-14).
    class AddressesController < BaseController
      def index
        text = params[:q].to_s
        return render json: { error: "Enter at least 3 characters" }, status: :unprocessable_content if text.strip.length < 3

        @addresses = Address.search(text)
      end
    end
  end
end
