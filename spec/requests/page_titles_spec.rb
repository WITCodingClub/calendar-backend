# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Page titles", type: :request do
  it "names the docs tab after the page" do
    get "/docs/api"

    expect(response.body).to include("<title>Course Catalog API — WIT Calendar</title>")
  end

  it "names the error tab after the error" do
    get "/404"

    expect(response.body).to include("<title>404 Not Found — WIT Calendar</title>")
  end
end
