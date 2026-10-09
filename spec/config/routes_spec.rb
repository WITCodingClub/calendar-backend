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

  # api_friends.rb draws the :friend_id routes last. If they move up, they
  # catch "meetings", "requests", and "groups" as a friend id.
  describe "friend routes" do
    def recognize(method, path) = Rails.application.routes.recognize_path(path, method: method)

    it "sends the fixed friend paths to their own controllers" do
      expect(recognize(:delete, "/api/friends/meetings/abc")).to include(controller: "api/friends/meetings", action: "destroy")
      expect(recognize(:delete, "/api/friends/requests/abc")).to include(controller: "api/friends/requests", action: "destroy")
      expect(recognize(:get, "/api/friends/groups")).to include(controller: "api/friends/groups", action: "index")
    end

    it "sends any other segment to the friend routes as a friend id" do
      expect(recognize(:delete, "/api/friends/abc")).to include(controller: "api/friends", action: "destroy", friend_id: "abc")
      expect(recognize(:get, "/api/friends/abc/visibility")).to include(controller: "api/friends/visibilities", action: "show")
    end
  end
end
