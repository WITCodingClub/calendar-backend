# frozen_string_literal: true

module Friendships
  # The friends feature flags of one user. The API, the dashboard, the views
  # and the MCP tools read the flags here.
  module Features
    module_function

    def availability_only?(user) = Flipper.enabled?(FeatureFlags::FRIENDS_AVAILABILITY_ONLY, user)
    def expiry?(user)            = Flipper.enabled?(FeatureFlags::FRIEND_EXPIRY, user)
    def groups?(user)            = user.present? && Flipper.enabled?(FeatureFlags::FRIEND_GROUPS, user)

    # While the viewer's availability-only flag is off, busy times are open only
    # for a friend who shares availability only: the full schedule answers 403
    # then, and the viewer needs this data. A list of friends passes the
    # viewer's flag, read once.
    def busy_times_readable?(friendship, viewer, flag_on: availability_only?(viewer))
      flag_on || !friendship.full_schedule_visible_to?(viewer)
    end
  end
end
