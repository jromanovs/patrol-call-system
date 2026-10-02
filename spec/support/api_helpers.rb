# 4.2: a request to the API with the personal API key of a user, and its
# answer as JSON.
module ApiHelpers
  def api_get(path, user:, params: {})
    get path, params:, headers: { "Authorization" => "Bearer #{user.issue_api_key}" }
    response.parsed_body
  end

  # POST, PATCH or DELETE with a JSON body; the answer, if it has one.
  def api_send(method, path, user:, body: {})
    public_send(method, path, params: body.is_a?(String) ? body : body.to_json,
                              headers: { "Authorization" => "Bearer #{user.issue_api_key}",
                                         "Content-Type" => "application/json" })
    response.body.empty? ? nil : response.parsed_body
  end
end

RSpec.configure do |config|
  config.include ApiHelpers, type: :request
end
