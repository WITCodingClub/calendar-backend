# frozen_string_literal: true

module McpTools
  class ListFriends < BaseTool
    tool_name "list_friends"
    title "List my friends"
    description "Lists my friends on WIT Calendar, with the id that friend_busy_times takes."
    requires_scope "friends:read"
    input_schema(properties: {})
    output_schema(Schemas.object(friends: Schemas.array(Schemas::FRIEND)))

    def perform
      authorize :friendship, :index?

      friends = user.accepted_friendships.includes(:requester, :addressee).map do |friendship|
        FriendSerializer.new(friendship.friend_for(user)).as_json
      end

      { friends: friends }
    end
  end
end
