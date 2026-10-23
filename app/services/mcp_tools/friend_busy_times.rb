# frozen_string_literal: true

module McpTools
  # A friend's busy times, with no course data. The rules are the same as
  # GET /api/friends/:friend_id/busy_blocks (Api::Friends::SchedulesController).
  class FriendBusyTimes < BaseTool
    tool_name "friend_busy_times"
    title "A friend's busy times"
    description "Lists the times a friend is busy between two dates, with no course details. " \
                "Use it to find a free time to meet. At most #{BusyBlocks::MAX_DAYS} days."
    requires_scope "friends:read"
    input_schema(
      properties: {
        friend_id:  { type: "string", description: "The friend id from list_friends." },
        start_date: DATE_SCHEMA,
        end_date:   DATE_SCHEMA
      },
      required: %w[friend_id start_date end_date]
    )
    output_schema(Schemas.object(Schemas::BUSY_TIMES_PROPERTIES.merge(friend: Schemas::FRIEND)))
    # The friend page shows the week of start_date. The friend id is the
    # public id that the page uses in its own URL, and the result has it too.
    links do |result|
      [
        page_link(
          name:        "wit-calendar-friend",
          title:       "#{result.dig(:friend, :name)} on WIT Calendar",
          url:         page_url(:dashboard_friend_url, result.dig(:friend, :id), week_start: result[:start_date]),
          description: "What this friend shares with you, for the week of #{result[:start_date]}."
        )
      ]
    end

    def perform(friend_id:, start_date:, end_date:)
      friendship = find_friendship(friend_id)
      authorize friendship, :view_availability?
      ensure_readable!(friendship)

      from, to = date_range(start_date, end_date)
      friend   = friendship.friend_for(user)

      BusyBlocksSerializer.new(BusyBlocks.new(friend, from: from, to: to).call, from: from, to: to)
                          .as_json.merge(friend: FriendSerializer.new(friend).as_json)
    end

    private

    def find_friendship(friend_id)
      friend = User.find_by_public_id(friend_id)
      friendship = friend && Friendship.accepted_between(user, friend)
      friendship || raise(ToolError, "You are not friends with #{friend_id}. Call list_friends for the ids.")
    end

    # While the availability-only flag is off, busy times are open only for a
    # friend who shares availability only (Api::FriendLookup#readable_without_flag?).
    def ensure_readable!(friendship)
      return if Flipper.enabled?(FeatureFlags::FRIENDS_AVAILABILITY_ONLY, user)
      return unless friendship.full_schedule_visible_to?(user)

      raise ToolError, "Busy times for this friend are not available yet."
    end
  end
end
