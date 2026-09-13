# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Favicon", type: :request do
  it "serves /favicon.ico" do
    get "/favicon.ico"

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to be_empty
  end

  it "serves the icon that the layouts link to" do
    get "/icon.png"

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("image/png")
  end

  it "links the icons from the docs layout" do
    get "/docs/api"

    expect(response.body).to include('<link rel="icon" href="/favicon.ico" sizes="48x48">')
    expect(response.body).to include('<link rel="apple-touch-icon" href="/icon.png">')
  end

  it "links the icons from the error pages" do
    get "/404"

    expect(response.body).to include('<link rel="icon" href="/favicon.ico" sizes="48x48">')
  end
end
