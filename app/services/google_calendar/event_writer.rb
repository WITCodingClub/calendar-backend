# frozen_string_literal: true

module GoogleCalendar
  # Writes one schedule event to Google Calendar and keeps its calendar_events
  # row in step: insert, update (with the person's own edits kept), and delete.
  #
  # The event data it gets already has the person's preferences applied.
  # GoogleCalendar::Provider applies them, because it needs them to decide
  # whether an event changed. Every call goes through the rate limiter it is
  # given (GoogleCalendar::Provider).
  class EventWriter
    SYNCABLE_ID_KEYS = %i[meeting_time_id final_exam_id university_calendar_event_id].freeze

    def initialize(user, rate_limiter:)
      @user         = user
      @rate_limiter = rate_limiter
    end

    # Inserts the event and creates its row. course_event gives the record the
    # row tracks, and event_data gives what Google gets.
    def create(service, course_calendar, course_event, event_data, labels: nil)
      calendar_id  = course_calendar.external_calendar_id
      google_event = EventPayload.build(event_data, labels)

      created_event = rate_limiter.with_rate_limit_handling do
        service.insert_event(calendar_id, google_event, **EventPayload.request_options(google_event))
      end

      course_calendar.calendar_events.create!(row_attributes(created_event, course_event, event_data))
    rescue ActiveRecord::RecordNotUnique
      # A concurrent sync already created the tracking row for this event, so the
      # insert_event above produced a duplicate remote event. Remove the duplicate
      # we just created rather than leaving it orphaned on the calendar.
      Rails.logger.warn({ message: "Duplicate event race — removing redundant remote event",
                          user_id: user&.id, calendar_id: calendar_id, external_event_id: created_event&.id }.to_json)
      rate_limiter.with_rate_limit_handling { service.delete_event(calendar_id, created_event.id) } if created_event&.id
      nil
    end

    # Without force, the person's edits in Google win: an edited field keeps
    # the person's value, and an edited recurrence keeps the whole event.
    # An event that is gone from Google is made again.
    #
    # Returns :updated, :skipped_no_change, :skipped_user_edit, or :recreated.
    def update(service, course_calendar, db_event, course_event, force: false, labels: nil)
      unless force || db_event.data_changed?(course_event)
        db_event.mark_synced!
        return :skipped_no_change
      end

      calendar_id         = course_calendar.external_calendar_id
      current_gcal_event  = nil
      newly_edited_fields = []

      unless force
        begin
          current_gcal_event = rate_limiter.with_rate_limit_handling { service.get_event(calendar_id, db_event.external_event_id) }
          edits              = EventEdits.new(db_event, current_gcal_event)

          newly_edited_fields = edits.edited_fields

          if edits.recurrence_changed?
            Rails.logger.info "User edited recurrence in Google Calendar: #{db_event.external_event_id}. Preserving user changes."
            keep_remote_event(db_event, edits)
            db_event.mark_synced!
            return :skipped_user_edit
          end
        rescue Google::Apis::ClientError => e
          raise unless e.status_code == 404

          Rails.logger.warn({ message: "Event not found in Google Calendar, recreating",
                              user_id: user.id, external_event_id: db_event.external_event_id }.to_json)
          db_event.destroy
          create(service, course_calendar, course_event, course_event, labels: labels)
          return :recreated
        end
      end

      all_edited_fields = force ? [] : ((db_event.user_edited_fields || []) + newly_edited_fields).uniq

      merged_event_data = if all_edited_fields.any? && current_gcal_event
                            EventEdits.new(db_event, current_gcal_event).merge(course_event, all_edited_fields)
      else
                            course_event.dup
      end

      google_event = EventPayload.build(merged_event_data, labels)
      rate_limiter.with_rate_limit_handling do
        service.update_event(calendar_id, db_event.external_event_id, google_event, **EventPayload.request_options(google_event))
      end

      db_event.update!(
        summary:            merged_event_data[:summary],
        location:           merged_event_data[:location],
        start_time:         merged_event_data[:start_time],
        end_time:           merged_event_data[:end_time],
        recurrence:         merged_event_data[:recurrence],
        event_data_hash:    CalendarEvent.generate_data_hash(merged_event_data),
        last_synced_at:     Time.current,
        user_edited_fields: all_edited_fields.any? ? all_edited_fields : nil
      )

      Rails.logger.info({ message: "Google Calendar event updated", user_id: user.id,
                          external_event_id: db_event.external_event_id, forced: force,
                          color_id: merged_event_data[:color_id], user_edited_fields: all_edited_fields }.to_json)

      :updated
    end

    # Deletes the event and its row. An event that is already gone from Google
    # only loses its row.
    def delete(service, course_calendar, db_event)
      calendar_id = course_calendar.external_calendar_id
      rate_limiter.with_rate_limit_handling { service.delete_event(calendar_id, db_event.external_event_id) }
      db_event.skip_remote_deletion = true
      db_event.destroy
    rescue Google::Apis::ClientError => e
      raise unless self.class.event_already_deleted?(e)

      Rails.logger.warn({ message: "Event not found in Google Calendar, removing from database",
                          user_id: user.id, external_event_id: db_event.external_event_id }.to_json)
      db_event.skip_remote_deletion = true
      db_event.destroy
    end

    # Google answers 404 for an event it never had, and 410 Gone for an event
    # that was already deleted, for example by the user in Google Calendar.
    # A delete has nothing left to do in both cases.
    def self.event_already_deleted?(error)
      [ 404, 410 ].include?(error.status_code)
    end

    private

    attr_reader :user, :rate_limiter

    def row_attributes(created_event, course_event, event_data)
      attributes = {
        external_event_id: created_event.id,
        summary:           event_data[:summary],
        location:          event_data[:location],
        start_time:        event_data[:start_time],
        end_time:          event_data[:end_time],
        recurrence:        event_data[:recurrence],
        event_data_hash:   CalendarEvent.generate_data_hash(event_data),
        last_synced_at:    Time.current
      }

      id_key = SYNCABLE_ID_KEYS.find { |key| course_event[key] }
      attributes[id_key] = course_event[id_key] if id_key
      attributes
    end

    def keep_remote_event(db_event, edits)
      db_event.update!(edits.remote_row_attributes)
      Rails.logger.info "Updated local DB with user's Google Calendar edits for event: #{db_event.external_event_id}"
    end
  end
end
