# frozen_string_literal: true

module FriendMeetings
  # Runs FriendMeetings::Publisher#resume after a person connects a calendar
  # account again: it finishes the meetings they deleted while the token was
  # refused, and puts back the events that a disconnect removed.
  #
  # It takes CourseCalendars::UserLock, so it
  # never runs at the same time as a sync or another meeting job for the
  # person.
  class ResumeJob < ApplicationJob
    include CourseCalendars::UserLock

    queue_as :default

    limits_concurrency_per_user(&:id)

    def perform(user)
      FriendMeetings::Publisher.new(user).resume
    end
  end
end
