# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Error pages" do
  it "renders the not found page as HTML" do
    get "/404"

    expect(response).to have_http_status(:not_found)
    expect(response.media_type).to eq("text/html")
  end

  it "returns 404, not 500, for a missing image" do
    get "/404.png"

    expect(response).to have_http_status(:not_found)
    expect(response.media_type).to eq("text/html")
  end

  it "returns 404, not 500, for a missing font" do
    get "/404.woff2"

    expect(response).to have_http_status(:not_found)
  end

  it "returns 422 for a JSON request" do
    get "/422.json"

    expect(response).to have_http_status(:unprocessable_content)
  end

  it "returns 500 for a PHP probe" do
    get "/500.php"

    expect(response).to have_http_status(:internal_server_error)
  end
end
