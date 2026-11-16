# frozen_string_literal: true

module CourseCalendars
  # The provider-neutral half of a calendar sync. It owns the sync loop (the
  # tracking rows by key, the delete of events the person no longer has, and
  # create, update or skip by the data hash), the "edits in the calendar win"
  # merge, the row columns, the duplicate race, and the "event is gone, make
  # it again" step. GoogleCalendar::Provider and MicrosoftGraph::CalendarProvider
  # subclass it and make only the remote calls.
  #
  # A subclass implements:
  #
  #   #course_calendar                                  -> CourseCalendar or nil
  #   #create_or_get_course_calendar(**options)          -> the calendar id; makes the calendar when it is missing
  #   #insert_event(calendar, event)                     -> the row's external id columns
  #   #fetch_event(row)                                  -> CourseCalendars::RemoteEvent, or nil when gone
  #   #patch_event(row, event_id, event, remote:, force:) -> the event id, or nil when gone
  #   #delete_event(row)                                -> deletes it; a missing event counts as deleted
  #   #delete_duplicate_event(calendar, event_id, notify:) -> deletes an event the app just made twice;
  #                                                        notify: true tells the invited friends
  #   #insert_friend_meeting(calendar, meeting, invite:)         -> the row's external id columns
  #   #patch_friend_meeting(row, meeting, attendees:)            -> the event id, or nil when gone
  #   #delete_friend_meeting(row)                                -> deletes it; missing counts as deleted
  #   #declined_attendee_emails(row)                             -> [String]
  #   #rate_limited?(error)                                      -> true for its rate limit error
  #   #connect!                                                  -> authorizes before a sync (optional)
  #
  # CourseCalendars::Providers lists the subclasses and the class methods each
  # one answers for the models and jobs.
  class Provider
    CALENDAR_NAME = "WIT Courses"
    ENV_PREFIXES  = { "test" => "[TEST] ", "development" => "[DEV] ", "stage" => "[STAGE] " }.freeze

    # Outside production, the names the app gives a calendar start with a
    # prefix, so a test calendar is never taken for the real one.
    def self.env_prefix
      ENV_PREFIXES[Rails.env].to_s
    end

    def self.calendar_name
      "#{env_prefix}#{CALENDAR_NAME}"
    end

    # The name that CourseCalendar#provider and OauthCredential#provider store.
    def self.provider_name
      Providers::CLASSES.key(name)
    end

    attr_reader :user

    # credential: the account to use, when the person has more than one.
    def initialize(user, credential: nil)
      @user       = user
      @credential = credential
    end

    # Makes the course calendar when the person has none, and then starts its
    # first sync, forced so the past events are filled in too. With
    # always_sync: true, an existing calendar gets a sync too, forced when the
    # provider says a reconnect needs it (FORCE_SYNC_ON_RECONNECT). Returns
    # the calendar id.
    def ensure_course_calendar(always_sync: false, **options)
      before      = course_calendar&.external_calendar_id
      calendar_id = create_or_get_course_calendar(**options)
      created     = calendar_id != before

      if created || always_sync
        CourseCalendars.resync(user, force: created || self.class::FORCE_SYNC_ON_RECONNECT)
      end
      calendar_id
    end

    # Makes each CourseCalendars::Event the person has, updates each one that
    # changed, and deletes each tracked event that is no longer wanted. An
    # event that is fully in the past stays: UniversityEventPruner removes those.
    def update_calendar_events(events, force: false)
      calendar = course_calendar
      return empty_stats unless calendar

      neutral_rate_limit do
        connect!
        existing = calendar.calendar_events.schedule_events.to_a.index_by(&:source_key)
        delete_rows(existing.except(*events.map(&:source_key)).values.reject { |row| fully_past?(row) })

        stats = upsert(calendar, events, existing, force: force)
        calendar.mark_synced!
        Rails.logger.info({ message: "Calendar sync completed", provider: calendar.provider, user_id: user.id, **stats }.to_json)
        stats
      end
    end

    # Makes or updates only the given events, and deletes nothing.
    def update_specific_events(events, force: false)
      calendar = course_calendar
      return empty_stats unless calendar

      neutral_rate_limit do
        connect!
        rows     = calendar.calendar_events.schedule_events
        existing = events.group_by { |event| event.source_key.first }
                         .map { |column, group| rows.where(column => group.map { |event| event.source.id }) }
                         .reduce(:or)&.index_by(&:source_key) || {}
        upsert(calendar, events, existing, force: force)
      end
    end

    # Deletes the events and their rows. For the events that the reconcile in
    # update_calendar_events keeps, such as past university events.
    def delete_events(rows)
      rows = Array(rows)
      return 0 if rows.empty? || course_calendar.nil?

      delete_rows(rows)
      rows.size
    end

    # Puts a FriendMeeting in the calendar and tracks it with a CalendarEvent
    # row. With invite: true and invitees, the provider sends each invitee an
    # invitation. Returns the row, or nil when the person has no course
    # calendar with this provider.
    def create_friend_meeting_event(meeting, invite: true)
      calendar = course_calendar
      return nil unless calendar

      remote = insert_friend_meeting(calendar, meeting, invite: invite)
      track_new_event(calendar, remote, row_attributes(meeting.calendar_event).merge(remote).merge(friend_meeting: meeting), notify: invite)
    end

    # Writes the meeting's current title, place, time, and (with attendees:
    # true) friends over the event. The provider tells each friend about the
    # change, and sends a cancellation to a friend who is no longer on the
    # list. An event that is gone is made again, without attendees.
    def update_friend_meeting_event(row, meeting, attendees:)
      event_id = patch_friend_meeting(row, meeting, attendees: attendees)

      if event_id.blank?
        row.skip_remote_deletion = true
        row.destroy!
        return create_friend_meeting_event(meeting, invite: false)
      end

      row.update!(row_attributes(meeting.calendar_event).merge(external_event_id: event_id))
      row
    end

    # Deletes the event of a meeting that its owner cancelled. The provider
    # sends a cancellation to each friend on the event.
    def delete_friend_meeting_event(row)
      delete_friend_meeting(row)
      row.skip_remote_deletion = true
      row.destroy!
    end

    private

    def empty_stats
      { created: 0, updated: 0, skipped: 0 }
    end

    # Each provider raises its own error for a rate limit. The jobs retry one
    # error class, so it leaves a sync as CourseCalendars::RateLimitError.
    def neutral_rate_limit
      yield
    rescue StandardError => e
      raise RateLimitError, e.message if rate_limited?(e)

      raise
    end

    # Authorizes with the provider before the sync looks at any row, so a
    # refused grant fails the sync also when no event changed.
    def connect!; end

    # A subclass can wait between deletes, to stay under a rate limit.
    def each_paced(rows, &)
      rows.each(&)
    end

    def delete_rows(rows)
      each_paced(rows) do |row|
        delete_event(row)
        row.skip_remote_deletion = true
        row.destroy
      end
    end

    def upsert(calendar, events, existing, force:)
      stats = empty_stats

      events.each do |event|
        row = existing[event.source_key]

        if row.nil?
          stats[create_event(calendar, event) ? :created : :skipped] += 1
        elsif force || row.data_changed?(event)
          result = update_event(calendar, row, event, force: force)
          stats[%i[skipped_user_edit duplicate].include?(result) ? :skipped : :updated] += 1
        else
          row.mark_synced!
          stats[:skipped] += 1
        end
      end

      stats
    end

    def create_event(calendar, event)
      remote = insert_event(calendar, event)
      row    = track_new_event(calendar, remote, row_attributes(event).merge(event.source_key.first => event.source.id).merge(remote))
      event_created(row, event) if row
      row
    end

    # Saves the row that tracks an event the provider just made. When a
    # concurrent sync already tracks the same source, the event is a
    # duplicate: it is deleted and the result is nil. The other sync's row
    # can be committed before the uniqueness validation runs (RecordInvalid
    # with :taken) or only before the insert (RecordNotUnique). The savepoint
    # keeps a RecordNotUnique from aborting a transaction the caller has open.
    # notify: true tells the friends invited to the duplicate that it is gone.
    def track_new_event(calendar, remote, attributes, notify: false)
      CalendarEvent.transaction(requires_new: true) { calendar.calendar_events.create!(attributes) }
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid => e
      raise if e.is_a?(ActiveRecord::RecordInvalid) && !source_taken?(e.record)

      Rails.error.report(e, handled: true, context: { user_id: user.id, calendar_id: calendar.id })
      remove_duplicate(calendar, remote[:external_event_id], notify: notify)
      nil
    end

    # A failed delete leaves the duplicate in the calendar, but the other
    # sync's row is good, so the sync goes on. The report names the event.
    def remove_duplicate(calendar, event_id, notify:)
      delete_duplicate_event(calendar, event_id, notify: notify)
    rescue StandardError => e
      Rails.error.report(e, handled: true, context: { user_id: user.id, calendar_id: calendar.id, external_event_id: event_id })
    end

    def source_taken?(row)
      CalendarEvent::SOURCE_COLUMNS.values.any? { |column| row.errors.of_kind?(column, :taken) }
    end

    # A hook for the work a provider does after the row of a new event exists.
    def event_created(_row, _event); end

    # Without force, the person's edits in their calendar win: an edited field
    # keeps the person's value, and an edited recurrence keeps the whole
    # event. A forced update writes the app's values and forgets the edits.
    # An event that is gone is made again.
    #
    # Returns :updated, :skipped_user_edit, :recreated, or :duplicate when a
    # concurrent sync made the event again first.
    def update_event(calendar, row, event, force:)
      event_id = row.external_event_id
      remote   = nil
      edited   = []
      merged   = event

      unless force
        remote = fetch_event(row)
        return recreate_event(calendar, row, event) if remote.nil?

        edits = EventEdits.new(row, remote)
        return keep_recurrence_edit(row, remote, edits) if edits.recurrence_changed?

        event_id = remote.id
        # Rows from before EventEdits stopped counting the description can still list it.
        edited = ((row.user_edited_fields || []) - [ "description" ] + edits.edited_fields).uniq
        merged = edits.merge(event, edited)
      end

      event_id = patch_event(row, event_id, merged, remote: remote, force: force)
      return recreate_event(calendar, row, event) if event_id.blank?

      # The hash is of the app's event, not the merged one. With the person's
      # edits in the hash, the next sync sees a change and updates again.
      row.update!(row_attributes(merged).merge(external_event_id: event_id, user_edited_fields: edited.presence,
                                               event_data_hash: event.data_hash))
      :updated
    end

    # The app cannot merge a series, so it keeps the event as the person left
    # it. The recurrence stays the one the app wrote, so the next sync still
    # sees the person's recurrence as an edit.
    def keep_recurrence_edit(row, remote, edits)
      Rails.logger.info({ message: "Recurrence edited in the calendar, keeping the event", user_id: user.id,
                          calendar_event_id: row.id }.to_json)
      attributes = edits.remote_attributes
      row.update!(attributes.merge(
        external_event_id: remote.id,
        event_data_hash:   Event.hash_of(attributes.merge(recurrence: row.recurrence)),
        last_synced_at:    Time.current
      ))
      :skipped_user_edit
    end

    def recreate_event(calendar, row, event)
      Rails.logger.warn({ message: "Event not found in the calendar, recreating", user_id: user.id,
                          calendar_event_id: row.id }.to_json)
      row.skip_remote_deletion = true
      row.destroy!
      create_event(calendar, event) ? :recreated : :duplicate
    end

    def row_attributes(event)
      {
        summary:         event.summary,
        location:        event.location,
        start_time:      event.start_time,
        end_time:        event.end_time,
        recurrence:      event.recurrence&.lines,
        event_data_hash: event.data_hash,
        last_synced_at:  Time.current
      }
    end

    # True only when the event, with its whole recurrence, is in the past.
    # end_time is the end of the first occurrence, so a series ends at its UNTIL.
    def fully_past?(row)
      recurrence = Recurrence.parse(row.recurrence)
      recurrence ? recurrence.ended? : row.end_time&.past?
    end
  end
end
