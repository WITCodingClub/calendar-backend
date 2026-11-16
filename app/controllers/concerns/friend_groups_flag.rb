# frozen_string_literal: true

# The flag gate of every friend group endpoint and page.
module FriendGroupsFlag
  extend ActiveSupport::Concern

  included do
    require_feature FeatureFlags::FRIEND_GROUPS, "Friend groups are not enabled"
  end
end
