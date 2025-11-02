class JsonWebTokenService
  SECRET_KEY = Rails.application.credentials.secret_key_base || Rails.application.secret_key_base

  def self.encode(payload, exp = 24.hours.from_now)
    payload[:exp] = exp.to_i if exp.present?
    JWT.encode(payload, SECRET_KEY)
  end

  def self.decode(token)
    # Decode without verifying expiration first to check if exp claim exists
    decoded = JWT.decode(token, SECRET_KEY, true, { verify_expiration: false, algorithm: 'HS256' })[0]

    # If exp claim exists, verify it manually (this will raise if expired)
    if decoded['exp']
      decoded = JWT.decode(token, SECRET_KEY, true, { algorithm: 'HS256' })[0]
    end

    HashWithIndifferentAccess.new(decoded)
  rescue JWT::DecodeError, JWT::ExpiredSignature
    nil
  end
end
