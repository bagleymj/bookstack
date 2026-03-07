module ApiHelpers
  def jwt_headers(user)
    token = JwtToken.encode(user)
    { "Authorization" => "Bearer #{token}" }
  end

  def json_response
    JSON.parse(response.body)
  end
end

RSpec.configure do |config|
  config.include ApiHelpers, type: :request
end
