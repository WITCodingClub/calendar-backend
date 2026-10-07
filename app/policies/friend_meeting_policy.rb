# frozen_string_literal: true

class FriendMeetingPolicy < ApplicationPolicy
  # Any signed-in person can make a meeting. FriendMeetingCreator checks that
  # each invited person is an accepted friend.
  def create? = user.present?
end
