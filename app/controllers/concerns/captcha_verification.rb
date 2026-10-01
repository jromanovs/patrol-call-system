# Checks the ALTCHA proof-of-work solution sent with a form. verify_altcha is
# false when the solution is missing, malformed, expired, signed by someone
# else or already used: a used nonce is remembered in the cache until the
# challenge expires.
#
# Secrets come from the encrypted credentials (altcha: hmac_secret,
# hmac_key_secret); outside production they are derived from secret_key_base.
module CaptchaVerification
  extend ActiveSupport::Concern

  NONCE_PREFIX = "altcha:nonce:"

  def self.secret(name)
    Rails.application.credentials.dig(:altcha, name) || derived_secret(name)
  end

  def self.derived_secret(name)
    raise "altcha.#{name} is missing in the production credentials" if Rails.env.production?

    ActiveSupport::KeyGenerator.new(Rails.application.secret_key_base).generate_key("altcha/#{name}", 32).unpack1("H*")
  end

  private

  def verify_altcha(field = :altcha)
    payload = decode_altcha(params[field].to_s)
    return false unless payload
    return false if Rails.cache.exist?(NONCE_PREFIX + payload.challenge.parameters.nonce)

    result = Altcha::V2.verify_solution(payload.challenge, payload.solution,
                                        hmac_signature_secret: CaptchaVerification.secret(:hmac_secret),
                                        hmac_key_signature_secret: CaptchaVerification.secret(:hmac_key_secret))
    result.verified && remember_nonce(payload.challenge)
  end

  def decode_altcha(encoded)
    return if encoded.empty?

    Altcha::V2::Payload.from_json(Base64.decode64(encoded))
  rescue JSON::ParserError, KeyError, ArgumentError, NoMethodError, TypeError
    nil
  end

  # The challenge carries its expiry in seconds since the epoch.
  def remember_nonce(challenge)
    ttl = challenge.parameters.expires_at.to_i - Time.now.to_i
    Rails.cache.write(NONCE_PREFIX + challenge.parameters.nonce, true, expires_in: ttl.seconds) if ttl.positive?
    true
  end
end
