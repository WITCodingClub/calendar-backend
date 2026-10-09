# frozen_string_literal: true

require "rails_helper"

# config/routes.rb loads the files in config/routes/ with draw. A file that no
# draw call names adds no routes, and nothing else fails.
RSpec.describe "Route files" do
  it "draws every file in config/routes exactly once" do
    files = Rails.root.glob("config/routes/*.rb").map { |path| path.basename(".rb").to_s }
    # A route file may draw another one, as api.rb draws api_legacy.rb.
    sources = [ Rails.root.join("config/routes.rb"), *Rails.root.glob("config/routes/*.rb") ]
    drawn   = sources.flat_map { |path| path.read.scan(/^\s*draw :(\w+)/).flatten }

    expect(drawn).to match_array(files)
  end
end
