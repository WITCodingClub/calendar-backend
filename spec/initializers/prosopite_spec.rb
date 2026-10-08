# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Prosopite N+1 detection" do
  it "scans every request with the Rack middleware" do
    expect(Rails.application.middleware).to include(Prosopite::Middleware::Rack)
  end

  it "raises on an N+1 query in the test environment" do
    create_list(:room, 2)

    expect {
      Prosopite.scan { Room.order(:id).each(&:building) }
    }.to raise_error(Prosopite::NPlusOneQueriesError)
  end

  it "does not raise when the association is preloaded" do
    create_list(:room, 2)

    expect {
      Prosopite.scan { Room.includes(:building).order(:id).each(&:building) }
    }.not_to raise_error
  end
end
