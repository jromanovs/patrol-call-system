# Hands out ALTCHA challenges for the sign-in form. The cost is the number of
# PBKDF2 iterations per attempt; the secret counter lies in cost..cost*2, so a
# browser spends about 50-200 ms and a bot pays the same for every attempt.
# An environment may set its own cost in config.x.captcha.cost (small in test).
class CaptchaController < ApplicationController
  allow_unauthenticated_access
  skip_before_action :keep_crew_on_its_screen

  TTL = 5.minutes
  ALGORITHM = "PBKDF2/SHA-256"
  COST = 5_000

  def self.challenge(cost: Rails.configuration.x.captcha.cost || COST)
    Altcha::V2.create_challenge(
      Altcha::V2::CreateChallengeOptions.new(
        algorithm: ALGORITHM, cost: cost, counter: SecureRandom.random_number(cost..(cost * 2)),
        expires_at: TTL.from_now,
        hmac_signature_secret: CaptchaVerification.secret(:hmac_secret),
        hmac_key_signature_secret: CaptchaVerification.secret(:hmac_key_secret)
      )
    )
  end

  def challenge
    render json: self.class.challenge.to_h
  end
end
