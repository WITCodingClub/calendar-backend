# frozen_string_literal: true

module GoogleCalendar
  # The Google side of the provider interface that CourseCalendars::Providers
  # documents. It runs the sync and gives the work to its collaborators:
  #
  #   GoogleCalendar::CalendarManager   create, share, list, and delete the calendar
  #   GoogleCalendar::EventWriter       insert, update, and delete one event and its row
  #   GoogleCalendar::EventPayload      the Google::Apis::CalendarV3::Event for an event hash
  #   GoogleCalendar::EventEdits        the fields the person changed in Google
  #   GoogleCalendar::CalendarServices  authorized Google API services
  #
  # The collaborators call Google through this class's rate limiter, so the
  # settings in config/initializers/google_api_rate_limiting.rb apply to all.
  class Provider
    include GoogleCalendar::RateLimiter
    include CalendarEventPreparation

    attr_reader :user

    def initialize(user = nil)
      @user = user
    end

    def course_calendar
      CourseCalendar.google.for_user(user).first
    end

    def create_or_get_course_calendar
      course_calendar = CourseCalendar.google.for_user(user).first
      newly_created   = false

      if course_calendar.blank?
        google_api_calendar = calendar_manager.create_calendar
        primary_credential  = user.google_credential || user.google_credentials.first
        raise "No Google OAuth credentials found for user" unless primary_credential

        course_calendar = primary_credential.create_course_calendar!(
          external_calendar_id: google_api_calendar.id,
          summary:            google_api_calendar.summary,
          description:        google_api_calendar.description,
          time_zone:          google_api_calendar.time_zone
        )
        newly_created = true
      end

      calendar_id = course_calendar.external_calendar_id

      share_calendar_with_user(calendar_id)
      add_calendar_to_all_oauth_users(calendar_id)

      if newly_created && user.enrollments.any?
        CourseCalendars::SyncJob.perform_later(user, force: true)
      end

      calendar_id
    rescue Google::Apis::Error => e
      Rails.logger.error "Failed to create Google Calendar: #{e.message}"
      raise "Failed to create course calendar: #{e.message}"
    end

    def update_calendar_events(events, force: false)
      service         = user_calendar_service
      course_calendar = CourseCalendar.google.for_user(user).first
      return { created: 0, updated: 0, skipped: 0 } unless course_calendar

      calendar_id = course_calendar.external_calendar_id

      all_existing_events = course_calendar.calendar_events.schedule_events.to_a
      existing_events     = {}
      duplicates_to_delete = []

      all_existing_events.each do |e|
        event_key = build_event_key(e)

        if existing_events[event_key]
          if e.created_at > existing_events[event_key].created_at
            duplicates_to_delete << existing_events[event_key]
            existing_events[event_key] = e
          else
            duplicates_to_delete << e
          end
        else
          existing_events[event_key] = e
        end
      end

      if duplicates_to_delete.any?
        Rails.logger.info "Cleaning up #{duplicates_to_delete.size} duplicate calendar events"
        with_batch_throttling(duplicates_to_delete) do |cal_event|
          delete_event_from_calendar(service, course_calendar, cal_event)
        end
      end

      current_event_keys = events.map { |e| build_event_key_from_hash(e) }.compact

      events_to_delete = existing_events.except(*current_event_keys).reject do |_key, cal_event|
        event_fully_past?(cal_event)
      end
      with_batch_throttling(events_to_delete.values) do |cal_event|
        delete_event_from_calendar(service, course_calendar, cal_event)
      end

      stats              = { created: 0, updated: 0, skipped: 0 }
      preference_resolver = Preferences::Resolver.new(user)
      template_renderer   = Preferences::TemplateRenderer.new
      labels              = GoogleCalendar::EventLabels.new(service, calendar_id)
      preload_syncables(events)

      events.each do |event|
        event_key      = build_event_key_from_hash(event)
        existing_event = existing_events[event_key]

        if existing_event
          syncable             = resolve_syncable(event)
          event_with_prefs     = apply_preferences_to_event(syncable, event, preference_resolver: preference_resolver, template_renderer: template_renderer)

          if force || existing_event.data_changed?(event_with_prefs)
            result = update_event_in_calendar(service, course_calendar, existing_event, event_with_prefs, force: force, labels: labels)
            stats[:updated] += 1 if result == :updated
            stats[:skipped] += 1 if result == :skipped_user_edit
          else
            existing_event.mark_synced!
            stats[:skipped] += 1
          end
        else
          create_event_in_calendar(service, course_calendar, event, preference_resolver: preference_resolver,
                                                                    template_renderer: template_renderer, labels: labels)
          stats[:created] += 1
        end
      end

      course_calendar.mark_synced!

      total_processed  = stats[:created] + stats[:updated] + stats[:skipped]
      skip_percentage  = total_processed > 0 ? (stats[:skipped].to_f / total_processed * 100).round(2) : 0

      Rails.logger.info({
        message: "Calendar sync completed",
        user_id: user.id,
        events_created: stats[:created],
        events_updated: stats[:updated],
        events_skipped: stats[:skipped],
        total_processed: total_processed,
        skip_percentage: skip_percentage
      }.to_json)

      stats
    end

    def update_specific_events(events, force: false)
      service         = user_calendar_service
      course_calendar = CourseCalendar.google.for_user(user).first

      unless course_calendar
        Rails.logger.warn({ message: "Cannot update events - no Google Calendar found", user_id: user&.id, event_count: events.size }.to_json)
        return { created: 0, updated: 0, skipped: 0 }
      end

      meeting_time_ids    = events.filter_map { |e| e[:meeting_time_id] }
      final_exam_ids      = events.filter_map { |e| e[:final_exam_id] }
      university_event_ids = events.filter_map { |e| e[:university_calendar_event_id] }

      base_query = course_calendar.calendar_events.schedule_events
      conditions = []
      conditions << base_query.where(meeting_time_id: meeting_time_ids)         if meeting_time_ids.any?
      conditions << base_query.where(final_exam_id: final_exam_ids)             if final_exam_ids.any?
      conditions << base_query.where(university_calendar_event_id: university_event_ids) if university_event_ids.any?

      query = conditions.reduce { |q, c| q.or(c) } || base_query

      existing_events = query.index_by { |e| build_event_key(e) }

      preference_resolver = Preferences::Resolver.new(user)
      template_renderer   = Preferences::TemplateRenderer.new
      labels              = GoogleCalendar::EventLabels.new(service, course_calendar.external_calendar_id)
      stats = { created: 0, updated: 0, skipped: 0 }
      preload_syncables(events)

      events.each do |event|
        event_key      = build_event_key_from_hash(event)
        existing_event = existing_events[event_key]

        if existing_event
          syncable         = resolve_syncable(event)
          event_with_prefs = apply_preferences_to_event(syncable, event, preference_resolver: preference_resolver, template_renderer: template_renderer)

          if force || existing_event.data_changed?(event_with_prefs)
            update_event_in_calendar(service, course_calendar, existing_event, event_with_prefs, force: force, labels: labels)
            stats[:updated] += 1
          else
            existing_event.mark_synced!
            stats[:skipped] += 1
          end
        else
          create_event_in_calendar(service, course_calendar, event, preference_resolver: preference_resolver,
                                                                    template_renderer: template_renderer, labels: labels)
          stats[:created] += 1
        end
      end

      Rails.logger.info "Partial sync complete: #{stats[:created]} created, #{stats[:updated]} updated, #{stats[:skipped]} skipped"
      stats
    end

    # Delete tracked events from Google Calendar and from the database.
    # Used for events that the reconcile pass in update_calendar_events keeps,
    # such as past university events the user no longer wants.
    def delete_events(db_events)
      db_events = Array(db_events)
      return 0 if db_events.empty?

      course_calendar = CourseCalendar.google.for_user(user).first
      return 0 unless course_calendar

      service = user_calendar_service
      with_batch_throttling(db_events) do |db_event|
        delete_event_from_calendar(service, course_calendar, db_event)
      end

      db_events.size
    end

    # Puts a FriendMeeting in the course calendar and tracks it with a
    # CalendarEvent row. With invite: true and invitees, Google sends each
    # invitee an invitation. Returns the row, or nil when the person has no
    # Google course calendar.
    def create_friend_meeting_event(meeting, invite: true)
      course_calendar = CourseCalendar.google.for_user(user).first
      return nil unless course_calendar

      calendar_id   = course_calendar.external_calendar_id
      event_data    = meeting.event_data
      google_event  = GoogleCalendar::EventPayload.for_friend_meeting(meeting, attendees: invite)
      service       = user_calendar_service
      send_updates  = google_event.attendees.present? ? "all" : "none"
      created_event = with_rate_limit_handling { service.insert_event(calendar_id, google_event, send_updates: send_updates) }

      course_calendar.calendar_events.create!(
        friend_meeting_row_attributes(event_data).merge(friend_meeting: meeting, external_event_id: created_event.id)
      )
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid => e
      raise if e.is_a?(ActiveRecord::RecordInvalid) && !e.record.errors.of_kind?(:friend_meeting_id, :taken)

      # A concurrent publish already tracks this meeting, so the event just
      # created is a duplicate. Remove it rather than leave it on the calendar.
      with_rate_limit_handling { service.delete_event(calendar_id, created_event.id, send_updates: "none") } if created_event&.id
      nil
    end

    # Writes the meeting's current title, place, time, and (with attendees:
    # true) friends over the event. Google tells each friend about the change,
    # and sends a cancellation to a friend who is no longer on the list. An
    # event that is gone is made again, without attendees.
    def update_friend_meeting_event(row, meeting, attendees:)
      calendar_id  = row.course_calendar.external_calendar_id
      google_event = GoogleCalendar::EventPayload.for_friend_meeting(meeting, attendees: attendees)
      service      = user_calendar_service

      begin
        with_rate_limit_handling do
          service.update_event(calendar_id, row.external_event_id, google_event, send_updates: attendees ? "all" : "none")
        end
      rescue Google::Apis::ClientError => e
        raise unless [ 404, 410 ].include?(e.status_code)

        row.skip_remote_deletion = true
        row.destroy!
        return create_friend_meeting_event(meeting, invite: false)
      end

      row.update!(friend_meeting_row_attributes(meeting.event_data))
      row
    end

    # Deletes the event of a meeting that its owner cancelled. Google sends a
    # cancellation to each friend on the event. A missing event counts as
    # deleted.
    def delete_friend_meeting_event(row)
      calendar_id = row.course_calendar.external_calendar_id
      service     = user_calendar_service

      begin
        with_rate_limit_handling { service.delete_event(calendar_id, row.external_event_id, send_updates: "all") }
      rescue Google::Apis::ClientError => e
        raise unless [ 404, 410 ].include?(e.status_code)
      end

      row.skip_remote_deletion = true
      row.destroy!
    end

    # The emails, in lower case, of the attendees who declined the invitation
    # to a meeting event. A tentative answer is not a decline. A missing event
    # has none.
    def declined_attendee_emails(row)
      calendar_id = row.course_calendar.external_calendar_id
      event       = with_rate_limit_handling { user_calendar_service.get_event(calendar_id, row.external_event_id) }

      Array(event.attendees).select { |attendee| attendee.response_status == "declined" }
                            .map { |attendee| attendee.email.to_s.downcase }
    rescue Google::Apis::ClientError => e
      raise unless [ 404, 410 ].include?(e.status_code)

      []
    end

    def list_calendars
      calendar_manager.list_calendars
    end

    # Deletes a single event from a calendar using the service account (which owns
    # all app-created calendars). Used when a CalendarEvent row is destroyed
    # so the live Google event doesn't linger as an orphan. Treats a missing event
    # as success.
    def delete_calendar_event(calendar_id, external_event_id)
      service = service_account_calendar_service
      with_rate_limit_handling { service.delete_event(calendar_id, external_event_id) }
    rescue Google::Apis::ClientError => e
      raise unless GoogleCalendar::EventWriter.event_already_deleted?(e)

      Rails.logger.info("Event #{external_event_id} already absent from calendar #{calendar_id}")
    end

    def delete_calendar(calendar_id)
      calendar_manager.delete_calendar(calendar_id)
    end

    # Public: OauthCredential calls this when a Google account is disconnected.
    # Uses that account's own token, so call it before the token is revoked.
    def remove_calendar_from_user_list_for_email(calendar_id, email)
      calendar_manager.remove_from_calendar_list(calendar_id, email)
    end

    # Deletes the ACL rule that share_calendar_with_user added for the email.
    def unshare_calendar_with_email(calendar_id, email)
      calendar_manager.unshare_with_email(calendar_id, email)
    end

    private

    def calendar_manager
      @calendar_manager ||= GoogleCalendar::CalendarManager.new(user, rate_limiter: self)
    end

    def event_writer
      @event_writer ||= GoogleCalendar::EventWriter.new(user, rate_limiter: self)
    end

    # GoogleCalendar::CreateJob, CourseScheduleSyncable, and some rake tasks
    # call the next four with send. Specs stub user_calendar_service.
    def service_account_calendar_service
      GoogleCalendar::CalendarServices.service_account
    end

    def user_calendar_service
      GoogleCalendar::CalendarServices.for_user(user)
    end

    def share_calendar_with_user(calendar_id)
      calendar_manager.share_with_user(calendar_id)
    end

    def add_calendar_to_all_oauth_users(calendar_id)
      calendar_manager.add_to_all_calendar_lists(calendar_id)
    end

    def create_event_in_calendar(service, course_calendar, course_event, preference_resolver: nil, template_renderer: nil, labels: nil)
      syncable   = resolve_syncable(course_event)
      event_data = apply_preferences_to_event(syncable, course_event, preference_resolver: preference_resolver, template_renderer: template_renderer)

      event_writer.create(service, course_calendar, course_event, event_data, labels: labels)
    end

    # course_event already has the user's preferences applied: both callers apply
    # them to decide whether the event changed.
    def update_event_in_calendar(service, course_calendar, db_event, course_event, force: false, labels: nil)
      event_writer.update(service, course_calendar, db_event, course_event, force: force, labels: labels)
    end

    def delete_event_from_calendar(service, course_calendar, db_event)
      event_writer.delete(service, course_calendar, db_event)
    end

    def friend_meeting_row_attributes(event_data)
      {
        summary:         event_data[:summary],
        location:        event_data[:location],
        start_time:      event_data[:start_time],
        end_time:        event_data[:end_time],
        recurrence:      event_data[:recurrence],
        event_data_hash: CalendarEvent.generate_data_hash(event_data),
        last_synced_at:  Time.current
      }
    end
  end
end
