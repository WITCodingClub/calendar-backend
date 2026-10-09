# frozen_string_literal: true

# Writes a person's FriendMeetings to the provider calendars that each meeting
# picked (its FriendMeetingPublication rows). The ICS feed reads the meetings
# from the database, so it needs no step here.
#
# A meeting gets at most one CalendarEvent row in each course calendar, so a
# run that finds the row skips that calendar. That makes a retry safe, and it
# lets a sync put a meeting back after its event went missing.
#
# Invitations go out once. The publication that sends them records the time,
# and a meeting that comes back later comes back without attendees, so the
# friends get no second invitation.
class FriendMeetingPublisher
  # The provider refused the person's token. A retry cannot help until the
  # person connects the account again.
  AUTH_ERRORS = [ MicrosoftGraph::AuthError, Google::Apis::AuthorizationError ].freeze

  attr_reader :user

  def initialize(user, services: nil)
    @user     = user
    @services = services
  end

  # The providers that have a course calendar, for example ["google"].
  def calendar_providers
    targets.keys
  end

  # Tries every picked calendar, then raises the first error, so one failed
  # provider does not stop the others.
  def publish(meeting)
    return if meeting.cancelled?

    each_publication(meeting) do |publication, service, calendar|
      next publication.mark_published! if meeting.calendar_events.exists?(calendar_id: calendar.id)

      invite = publication.sends_invitations? && publication.invitations_sent_at.nil?
      service.create_friend_meeting_event(meeting, invite: invite)
      publication.mark_published!(invitations_sent: invite)
    end
  end

  # Writes the meeting's title, place, time, and friends to each event that
  # exists, and makes each event that is missing. An event gets attendees
  # only from the provider that sent the invitations, so a removed friend
  # gets a cancellation from that provider.
  def update(meeting)
    return if meeting.cancelled?

    each_publication(meeting) do |publication, service, calendar|
      row = meeting.calendar_events.find_by(calendar_id: calendar.id)

      if row
        service.update_friend_meeting_event(row, meeting, attendees: publication.invitations_sent_at.present?)
        publication.mark_published!
      else
        invite = publication.sends_invitations? && publication.invitations_sent_at.nil?
        service.create_friend_meeting_event(meeting, invite: invite)
        publication.mark_published!(invitations_sent: invite)
      end
    end
  end

  # Deletes every provider event of a cancelled meeting, then the meeting. A
  # provider sends a cancellation to each friend who got an invitation.
  #
  # A failed delete keeps its row and the cancelled meeting, so a retry, the
  # hourly FriendMeetingRemovalSweepJob, or a reconnect can finish. A refused
  # token is recorded on the publication and not raised, because only a
  # reconnect helps. Any other error is raised for the job to retry.
  def remove(meeting)
    errors = []
    kept   = false

    meeting.calendar_events.includes(:course_calendar).find_each do |row|
      provider = row.course_calendar.provider
      service  = targets[provider]&.first
      service ? service.delete_friend_meeting_event(row) : row.destroy!
    rescue *AUTH_ERRORS => e
      log_failure("Could not delete a friend meeting event: token refused", meeting, provider, e)
      meeting.publication_for(provider)&.mark_failed!(e.class.name)
      kept = true
    rescue StandardError => e
      log_failure("Could not delete a friend meeting event", meeting, provider, e)
      meeting.publication_for(provider)&.mark_failed!(e.class.name)
      errors << e
    end

    raise errors.first if errors.any?

    meeting.destroy! unless kept
  end

  # After the person connects an account again: finish each cancelled meeting
  # that still has provider events, then put back each missing event. Errors
  # are logged, so one meeting does not stop the others.
  def resume
    user.friend_meetings.where.not(cancelled_at: nil).find_each do |meeting|
      remove(meeting)
    rescue StandardError => e
      log_failure("Friend meeting removal failed on reconnect", meeting, nil, e)
    end

    publish_missing
  end

  # Puts back every meeting that has not ended and is missing from a picked
  # calendar. The course sync calls this, so a failure is logged and not
  # raised. A person with no meetings costs one indexed query.
  def publish_missing
    return unless user.friend_meetings.exists?

    user.friend_meetings.live.not_ended.includes(:publications).find_each do |meeting|
      publish(meeting)
    rescue StandardError => e
      log_failure("Friend meeting publish failed during sync", meeting, nil, e)
    end
  end

  private

  def each_publication(meeting)
    errors = []

    meeting.publications.calendars.order(:id).each do |publication|
      service, calendar = targets[publication.provider]
      unless calendar
        # A disconnected provider stays `removed` until the person connects
        # it again.
        publication.mark_failed!("no #{publication.provider} course calendar") unless publication.removed?
        next
      end

      yield publication, service, calendar
    rescue StandardError => e
      log_failure("Could not publish a friend meeting", meeting, publication.provider, e)
      publication.mark_failed!(e.class.name)
      errors << e
    end

    raise errors.first if errors.any?
  end

  def log_failure(message, meeting, provider, error)
    Rails.logger.error({ message: message, user_id: user.id, friend_meeting_id: meeting.id,
                         provider: provider, error: error.class.name }.compact.to_json)
  end

  def services
    @services ||= CourseCalendars::Providers.services_for(user)
  end

  # { "google" => [service, calendar], ... } for each connected calendar.
  def targets
    @targets ||= services.each_with_object({}) do |service, found|
      calendar = service.course_calendar
      found[calendar.provider] = [ service, calendar ] if calendar
    end
  end
end
