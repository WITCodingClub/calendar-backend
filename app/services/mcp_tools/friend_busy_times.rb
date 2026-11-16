# frozen_string_literal: true

module McpTools
  # A friend's busy times, with no course data (Friendships::BusyTimes).
  class FriendBusyTimes < BaseTool
    tool_name "friend_busy_times"
    title "A friend's busy times"
    description "Lists the times a friend is busy between two dates, with no course details. " \
                "Use it to find a free time to meet. At most #{BusyBlocks::MAX_DAYS} days."
    requires_scope "friends:read"
    meta BusyTimesApp.tool_meta
    input_schema(
      properties: {
        friend_id:  { type: "string", description: "The friend id from list_friends." },
        start_date: DATE_SCHEMA,
        end_date:   DATE_SCHEMA
      },
      required: %w[friend_id start_date end_date]
    )
    output_schema(Schemas.object(Schemas::BUSY_TIMES_PROPERTIES.merge(friend: Schemas::FRIEND)))
    # The friend page shows the friend's schedule or, for a friend who shares
    # availability only, the busy times of the week of start_date. The friend
    # id is the public id that the page uses in its own URL, and the result
    # has it too.
    links do |result|
      [
        onboarded_page_link(
          name:        "wit-calendar-friend",
          title:       "#{result.dig(:friend, :name)} on WIT Calendar",
          url:         page_url(:dashboard_friend_url, result.dig(:friend, :id), week_start: result[:start_date]),
          description: "What this friend shares with you: their class schedule, or only the times they are busy."
        )
      ]
    end

    def perform(friend_id:, start_date:, end_date:)
      friendship = find_friendship(friend_id)
      authorize friendship, :view_availability?
      busy_times = Friendships::BusyTimes.new(user, friendship)
      raise ToolError, "Busy times for this friend are not available yet." unless busy_times.readable?

      from, to = date_range(start_date, end_date)
      busy_times.as_json(from, to).merge(friend: FriendSerializer.new(friendship.friend_for(user)).as_json)
    end

    private

    def find_friendship(friend_id)
      friend = User.find_by_public_id(friend_id)
      friendship = friend && Friendship.accepted_between(user, friend)
      friendship || raise(ToolError, "You are not friends with #{friend_id}. Call list_friends for the ids.")
    end
  end
end
