# CRW-04, CRW-05, DYN-16: the crew screen turns the notices of the crew's car
# on and off for the phone it runs on.
class PushSubscriptionsController < ApplicationController
  skip_before_action :keep_crew_on_its_screen
  before_action { authorize :crew, :notices? }

  # A phone sent again belongs to the sign-in on it now, and is kept with the
  # language of the crew screen that sent it (USR-10).
  def create
    phone = PushSubscription.find_or_initialize_by(endpoint: params.expect(:endpoint))
    if phone.update(session: Current.session, locale: I18n.locale, **params.expect(keys: %i[ p256dh auth ]))
      head :created
    else
      render json: { error: phone.errors.full_messages.to_sentence }, status: :unprocessable_content
    end
  end

  def destroy
    Current.session.push_subscriptions.where(endpoint: params.expect(:endpoint)).delete_all
    head :no_content
  end
end
