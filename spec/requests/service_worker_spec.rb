require "rails_helper"

RSpec.describe "The service worker of the notices (CRW-04, BR-13)" do
  it "is served to everyone, as a script that holds no data", :aggregate_failures do
    get pwa_service_worker_path(format: :js)

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("text/javascript")
  end

  it "shows a notice as the server sent it and opens its page when tapped", :aggregate_failures do
    get pwa_service_worker_path(format: :js)

    expect(response.body).to include('addEventListener("push"', "showNotification(title, options)",
                                     'addEventListener("notificationclick"', "openWindow(path)")
  end
end
