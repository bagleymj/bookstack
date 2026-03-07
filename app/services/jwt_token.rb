module JwtToken
  ALGORITHM = "HS256"
  EXPIRATION = 30.days

  def self.secret
    Rails.application.credentials.devise_jwt_secret_key || Rails.application.secret_key_base
  end

  def self.encode(user)
    payload = {
      sub: user.id.to_s,
      jti: SecureRandom.uuid,
      iat: Time.current.to_i,
      exp: EXPIRATION.from_now.to_i
    }
    JWT.encode(payload, secret, ALGORITHM)
  end

  def self.decode(token)
    JWT.decode(token, secret, true, algorithm: ALGORITHM).first
  rescue JWT::DecodeError, JWT::ExpiredSignature
    nil
  end
end
