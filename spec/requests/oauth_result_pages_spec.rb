# frozen_string_literal: true

require "rails_helper"

RSpec.describe "OAuth result pages", type: :request do
  # The pages tell an opener window the result. Only this app's own pages may
  # read it, so no page may post to every origin.
  it "posts the success message to this origin only" do
    get "/oauth/success", params: { email: "person@example.com", calendar_id: "cal-1" }

    expect(response.body).not_to match(/postMessage\([^)]*['"]\*['"]/m)
    expect(response.body).to include("window.location.origin")
  end

  it "posts the failure message to this origin only" do
    get "/oauth/failure", params: { error: "nope" }

    expect(response.body).not_to match(/postMessage\([^)]*['"]\*['"]/m)
    expect(response.body).to include("window.location.origin")
  end
end
