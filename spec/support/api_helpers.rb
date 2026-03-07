module ApiHelpers
  def jwt_headers(user)
    token = Warden::JWTAuth::UserEncoder.new.call(user, :user, nil).first
    { "Authorization" => "Bearer #{token}" }
  end

  def json_response
    JSON.parse(response.body)
  end
end

RSpec.configure do |config|
  config.include ApiHelpers, type: :request
end
