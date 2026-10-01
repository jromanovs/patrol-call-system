# DYN-11: suggestions from the address register for the address field of a
# site; every signed-in user may read the register (BR-14).
class AddressesController < ApplicationController
  def index
    @text = params[:q].to_s
    @addresses = Address.search(@text)
  end
end
