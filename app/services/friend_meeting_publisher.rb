# frozen_string_literal: true

# Puts a person's FriendMeetings in the course calendar of each provider they
# sync to. The ICS feed reads the meetings from the database, so it needs no
# step here.
#
# A meeting gets at most one CalendarEvent row in each course calendar, so a
# run that finds the row skips that calendar. That makes a retry safe, and it
# lets a sync put a meeting back after its calendar was made again (a
# Microsoft placement move, or a calendar that the person deleted).
#
# Only the first calendar sends the invitations, so a person with a Google
# and a Microsoft calendar does not invite their friends twice.
class FriendMeetingPublisher
  attr_reader :user

  def initialize(user, services: nil)
    @user     = user
    @services = services
  end

  # The providers that get the meeting, for example ["google"].
  def calendar_providers
    targets.map { |_service, calendar| calendar.provider }
  end

  # Tries every calendar, then raises the first error, so one failed provider
  # does not stop the others.
  def publish(meeting)
    errors = []

    targets.each_with_index do |(service, calendar), index|
      next if meeting.calendar_events.exists?(calendar_id: calendar.id)

      service.create_friend_meeting_event(meeting, invite: index.zero?)
    rescue StandardError => e
      Rails.logger.error({ message: "Could not publish a friend meeting", user_id: user.id,
                           friend_meeting_id: meeting.id, provider: calendar.provider, error: e.class.name }.to_json)
      errors << e
    end

    raise errors.first if errors.any?
  end

  # Puts back every meeting that has not ended and is missing from a calendar.
  # The course sync calls this, so a failure is logged and not raised.
  def publish_missing
    meetings = user.friend_meetings.not_ended.to_a
    return if meetings.empty?

    meetings.each do |meeting|
      publish(meeting)
    rescue StandardError => e
      Rails.logger.error({ message: "Friend meeting publish failed during sync", user_id: user.id,
                           friend_meeting_id: meeting.id, error: e.class.name }.to_json)
    end
  end

  private

  def services
    @services ||= CalendarProviders.services_for(user)
  end

  def targets
    @targets ||= services.filter_map do |service|
      calendar = service.course_calendar
      [ service, calendar ] if calendar
    end
  end
end
