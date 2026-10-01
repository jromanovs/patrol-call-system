# A solved ALTCHA payload, as the widget submits it with the sign-in form.
module AltchaHelpers
  def altcha_payload
    challenge = CaptchaController.challenge
    solution = Altcha::V2.solve_challenge(challenge)
    Base64.strict_encode64(Altcha::V2::Payload.new(challenge: challenge, solution: solution).to_json)
  end
end

RSpec.configure do |config|
  config.include AltchaHelpers, type: :request
end
