# frozen_string_literal: true

require "rails_helper"

# Production keeps Rails.cache in Solid Cache (spec/config/production_security_spec.rb).
# The test environment uses a null store.
RSpec.describe "Solid Cache configuration" do
  # Solid Cache raises NotImplementedError on delete_matched. A call in app
  # code would pass in test (null store) and fail only in production.
  it "has no delete_matched call in app code" do
    callers = Rails.root.glob("{app,lib,config}/**/*.rb").select do |path|
      path.read.lines.any? { |line| line.match?(/\.delete_matched\b/) && !line.strip.start_with?("#") }
    end

    expect(callers).to be_empty
  end
end
