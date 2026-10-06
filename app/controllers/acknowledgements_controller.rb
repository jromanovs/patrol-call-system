# UPD-13: a dispatcher has seen a crew's SOS; its strip leaves every page.
class AcknowledgementsController < ApplicationController
  def create
    call = authorize SosCall.find(params.expect(:call_id)), :update?
    if call.acknowledge(Current.user)
      redirect_back_or_to root_path, notice: t(".acknowledged", car: call.raised_by.call_sign)
    else
      redirect_back_or_to root_path, alert: call.errors.full_messages.to_sentence
    end
  end
end
