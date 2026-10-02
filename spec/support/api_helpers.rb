# 4.2: a request to the API with the personal API key of a user, and its
# answer as JSON.
module ApiHelpers
  def api_get(path, user:, params: {})
    get path, params:, headers: { "Authorization" => "Bearer #{user.issue_api_key}" }
    response.parsed_body
  end
end

RSpec.configure do |config|
  config.include ApiHelpers, type: :request
end
