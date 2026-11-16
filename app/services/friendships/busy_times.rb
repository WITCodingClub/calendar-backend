# frozen_string_literal: true

module Friendships
  # A friend's busy times (BusyBlocks), with no course data. The API, the MCP
  # tool and the dashboard read them here. Each one authorizes
  # FriendshipPolicy#view_availability? first.
  class BusyTimes
    def initialize(viewer, friendship)
      @viewer     = viewer
      @friendship = friendship
    end

    # False while the busy times are not open to the viewer
    # (Features.busy_times_readable?).
    def readable? = Features.busy_times_readable?(@friendship, @viewer)

    def blocks(from, to)
      BusyBlocks.new(@friendship.friend_for(@viewer), from: from, to: to).call
    end

    def as_json(from, to)
      BusyBlocksSerializer.new(blocks(from, to), from: from, to: to).as_json
    end
  end
end
