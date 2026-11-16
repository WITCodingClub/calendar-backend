# frozen_string_literal: true

module MicrosoftGraph
  # The Microsoft Graph remote calls of CourseCalendars::Provider, which runs
  # the sync. The events go to a calendar in the person's own Microsoft 365
  # mailbox.
  #
  # Graph event ids change when an event moves between folders, but iCalUId does
  # not. Each tracking row keeps both. When Graph answers 404 for the stored id,
  # the service looks the event up by iCalUId, stores the new id and carries on.
  # Only when neither id finds the event does it create the event again.
  class CalendarProvider < CourseCalendars::Provider
    AUTH_ERRORS = [ MicrosoftGraph::AuthError ].freeze
    # Graph answers a rate limit with a 429, which the client raises as a
    # MicrosoftGraph::Error, so it is transient (#rate_limited?).
    RATE_LIMIT_ERRORS = [].freeze
    TRANSIENT_ERRORS  = [ MicrosoftGraph::Error ].freeze

    def self.syncs_for?(user)
      MicrosoftGraph.enabled_for?(user) && CourseCalendar.microsoft.for_user(user).exists?
    end

    # `placement` ("separate" or "primary") says where a first connection puts
    # the course events.
    def self.connect_path(user, placement: nil)
      state = MicrosoftGraph::OauthState.generate(user_id: user.id, placement: placement)
      Rails.application.routes.url_helpers.microsoft_graph_auth_path(state: state)
    end

    # invalid_grant means Microsoft will not take the refresh token again: the
    # person revoked access, an admin removed consent, or the token expired.
    def self.invalid_grant?(error)
      error.is_a?(MicrosoftGraph::AuthError) && error.body.is_a?(Hash) && error.body["error"] == "invalid_grant"
    end

    def self.delete_event_later(ref)
      MicrosoftGraph::EventDeleteJob.perform_later(ref[:oauth_credential_id], ref[:event_id], ref[:ical_uid])
    end

    def self.delete_calendar_later(calendar)
      MicrosoftGraph::CalendarDeleteJob.perform_later(calendar.oauth_credential_id, calendar.external_calendar_id)
    end

    # Microsoft credentials refresh only while the app has an Entra client.
    def self.refreshable?
      MicrosoftGraph.configured?
    end

    def self.refresh_token!(credential)
      MicrosoftGraph::TokenClient.new.refresh!(credential)
    end

    # A Microsoft calendar lives in the person's mailbox, and only this
    # credential's token can delete it. The delete job that destroying the row
    # would enqueue runs after the credential is gone, so the calendar goes
    # now. A Graph failure must not block the disconnect, so it is reported
    # only. When the events are in the person's primary calendar, only the
    # events go.
    def self.release_calendar(credential)
      calendar = credential.course_calendar
      return if calendar.nil? || calendar.external_calendar_id.blank?

      new(credential.user, credential: credential).remove_course_events(calendar)
    rescue StandardError => e
      Rails.error.report(e, handled: true, context: { oauth_credential_id: credential.id })
    ensure
      # The delete job would find no credential, so it is not enqueued.
      calendar&.skip_remote_deletion = true
    end

    # Microsoft has no revoke endpoint that the app can call for a grant.
    def self.revoke_later(_credential); end

    def initialize(user, credential: nil, client: nil)
      super(user, credential: credential)
      @client = client
    end

    def credential
      @credential ||= user&.oauth_credentials&.microsoft&.order(:created_at)&.first
    end

    def course_calendar
      return nil unless credential

      CourseCalendar.microsoft.find_by(oauth_credential_id: credential.id)
    end

    # `placement` applies only when the person has no calendar row yet. Use
    # #change_placement to move a calendar that exists.
    def create_or_get_course_calendar(placement: nil)
      raise MicrosoftGraph::AuthError, "No Microsoft credential found for user" unless credential

      calendar  = course_calendar
      placement = calendar&.placement || placement.presence || "separate"
      return use_primary_calendar(calendar) if placement == "primary"

      if calendar
        begin
          client.get("me/calendars/#{escape(calendar.external_calendar_id)}", params: { "$select" => "id" })
          return calendar.external_calendar_id
        rescue MicrosoftGraph::NotFoundError
          # The person deleted the calendar in Outlook, and its events went with
          # it. The tracking rows point at nothing, so they go too. Friend
          # meetings live in the primary calendar, so their rows stay.
          calendar.calendar_events.schedule_events.delete_all
        end
      end

      save_calendar(calendar, create_separate_calendar, placement: "separate")
    end

    # Moves the course events between a calendar of their own and the person's
    # primary calendar. The old events are deleted here. The caller starts a
    # forced sync, which creates them again in the new place. Edits the person
    # made in Outlook do not survive the move.
    #
    # Friend meetings are not part of the move. They always live in the
    # primary calendar (see #create_friend_meeting_event), so the friends get
    # no cancellation and no second invitation.
    #
    # A failed step can run again: the primary calendar id is read before
    # anything is deleted, a delete of a missing event or calendar counts as
    # done, and the move stops while an event delete has failed. One gap stays:
    # if the process dies after Graph creates the separate calendar and before
    # the row is saved, the next run creates a second, empty "WIT Courses"
    # calendar. The service does not look for a calendar by name, because it
    # could then adopt, and later delete, a calendar that the person made.
    def change_placement(placement)
      placement = placement.to_s
      raise ArgumentError, "unknown placement #{placement}" unless CourseCalendar::PLACEMENTS.value?(placement)

      calendar = course_calendar
      return create_or_get_course_calendar(placement: placement) unless calendar
      return calendar.external_calendar_id if calendar.placement == placement

      if placement == "primary"
        remote = fetch_primary_calendar
        delete_calendar(calendar.external_calendar_id)
        calendar.calendar_events.schedule_events.delete_all
      else
        delete_tracked_events(calendar.calendar_events.schedule_events)
        # A row that stays points at an event in the primary calendar. After the
        # move, the sync would find that row and update the old event in place.
        # So the move stops here, and the job tries again.
        if calendar.calendar_events.schedule_events.exists?
          raise MicrosoftGraph::Error, "could not delete every course event from the primary calendar"
        end

        remote = create_separate_calendar
      end

      save_calendar(calendar, remote, placement: placement)
    end

    # Removes what the app put in the mailbox: the whole calendar when it is the
    # app's own, or only the tracked events when they are in the primary
    # calendar. Friend meetings are always in the primary calendar, so they go
    # one by one.
    #
    # Deleting a meeting event sends its friends a cancellation, so each meeting
    # whose event went is marked `removed`, and the next publish after a
    # reconnect sends the invitations again.
    def remove_course_events(calendar)
      meeting_ids = calendar.calendar_events.friend_meetings_only.pluck(:friend_meeting_id)

      if calendar.primary_placement?
        delete_tracked_events(calendar.calendar_events)
      else
        delete_tracked_events(calendar.calendar_events.friend_meetings_only)
        delete_calendar(calendar.external_calendar_id)
      end

      mark_meetings_removed(calendar, meeting_ids)
    end

    # The emails, in lower case, of the attendees who declined the invitation
    # to a meeting event. A tentative answer is not a decline. A missing event
    # has none.
    def declined_attendee_emails(row)
      event = fetch_attendees(row.external_event_id)
      if event.nil?
        moved_id = find_event_id_by_ical_uid(row.external_ical_uid)
        event    = fetch_attendees(moved_id) if moved_id.present?
      end

      Array(event&.dig("attendees")).select { |attendee| attendee.dig("status", "response") == "declined" }
                                    .map { |attendee| attendee.dig("emailAddress", "address").to_s.downcase }
    end

    def delete_calendar_event(event_id, ical_uid = nil)
      client.delete(event_path(event_id))
    rescue MicrosoftGraph::NotFoundError
      moved_id = find_event_id_by_ical_uid(ical_uid)
      delete_quietly(moved_id) if moved_id.present? && moved_id != event_id
    end

    # Never deletes a calendar that a row tracks as the person's primary calendar.
    def delete_calendar(calendar_id)
      if CourseCalendar.microsoft.primary_placement.exists?(external_calendar_id: calendar_id)
        Rails.logger.error("Refused to delete a primary Microsoft calendar")
        return
      end

      client.delete("me/calendars/#{escape(calendar_id)}")
    rescue MicrosoftGraph::NotFoundError
      Rails.logger.info("Microsoft calendar #{calendar_id} already absent")
    end

    private

    def client
      @client ||= MicrosoftGraph::Client.new(credential)
    end

    def rate_limited?(error)
      error.is_a?(MicrosoftGraph::Error) && error.status == 429
    end

    # The primary calendar always exists, so there is nothing to create. Its id
    # is read again each time, because it is the only link to the mailbox.
    def use_primary_calendar(calendar)
      save_calendar(calendar, fetch_primary_calendar, placement: "primary")
    end

    def fetch_primary_calendar
      client.get("me/calendar", params: { "$select" => "id,name" })
    end

    def create_separate_calendar
      client.post("me/calendars", { name: self.class.calendar_name })
    end

    def save_calendar(calendar, remote, placement:)
      attributes = {
        external_calendar_id: remote.fetch("id"),
        summary:              remote["name"],
        time_zone:            SchoolTimeZone::NAME,
        placement:            placement
      }

      if calendar.nil?
        calendar = CourseCalendar.create!(attributes.merge(provider: self.class.provider_name, oauth_credential: credential))
      elsif calendar.external_calendar_id != attributes[:external_calendar_id] || calendar.placement != placement
        calendar.update!(attributes.merge(last_synced_at: nil))
      end

      calendar.external_calendar_id
    end

    def mark_meetings_removed(calendar, meeting_ids)
      gone = meeting_ids - calendar.calendar_events.friend_meetings_only.pluck(:friend_meeting_id)
      FriendMeetingPublication.where(friend_meeting_id: gone, provider: self.class.provider_name).find_each(&:mark_removed!)
    end

    # One failed delete must not stop the others, so it is reported and the
    # row stays. A row that stays is tried again on the next call.
    def delete_tracked_events(rows)
      rows.find_each do |row|
        delete_rows([ row ])
      rescue MicrosoftGraph::Error => e
        Rails.error.report(e, handled: true, context: { user_id: user&.id, calendar_event_id: row.id })
      end
    end

    def insert_event(calendar, data)
      remote = client.post("me/calendars/#{escape(calendar.external_calendar_id)}/events", event_payload(data))
      { external_event_id: remote["id"], external_ical_uid: remote["iCalUId"] }
    end

    # The row exists before the occurrences are cancelled, so a failure here
    # cannot make the next sync post the series again. The cleared hash makes
    # the next sync see a change and run the exclusions through an update.
    def event_created(row, data)
      cancel_excluded_occurrences(row.external_event_id, data)
    rescue MicrosoftGraph::Error, Faraday::Error => e
      Rails.error.report(e, handled: true, context: { user_id: user&.id, calendar_event_id: row.id })
      row.update_column(:event_data_hash, nil) # rubocop:disable Rails/SkipsModelValidations
    end

    # Reads the event by its stored id, then by its iCalUId. nil when neither
    # finds it.
    def fetch_event(row)
      event_id = row.external_event_id
      remote   = begin
        get_event(event_id)
      rescue MicrosoftGraph::NotFoundError
        event_id = find_event_id_by_ical_uid(row.external_ical_uid)
        return nil if event_id.blank?

        begin
          get_event(event_id)
        rescue MicrosoftGraph::NotFoundError
          return nil
        end
      end

      EventPayload.remote_event(row, event_id, remote)
    end

    def get_event(event_id)
      client.get(event_path(event_id), params: { "$select" => EventPayload::SELECT })
    end

    # Without a read of the event (a forced update), the WIT category is set
    # only when the event has a color, and no color clears the old one. After
    # a read, the person's own categories and free or busy choice stay.
    # Updating a series restores its occurrences, so the excluded ones are
    # cancelled again.
    def patch_event(row, event_id, data, remote:, force:)
      payload = event_payload(data, remote_categories: remote&.raw&.fetch("categories", nil))
      payload[:categories] ||= [] if force
      event_id = patch_tracked_event(row, event_id, payload)
      cancel_excluded_occurrences(event_id, data) if event_id.present?
      event_id
    end

    def delete_event(row)
      delete_calendar_event(row.external_event_id, row.external_ical_uid)
    end

    def delete_duplicate_event(_calendar, event_id)
      delete_quietly(event_id)
    end

    # A friend meeting goes to the person's primary calendar, whatever the
    # placement of the course events. The row still belongs to the course
    # calendar, which tracks it.
    #
    # Graph cannot move an event between calendars, and deleting a meeting with
    # attendees sends them a cancellation. In the primary calendar, a placement
    # move or a course calendar that the person deleted never touches the
    # meeting, so friends never get a cancellation and a new invitation for
    # nothing. Exchange also reads free and busy time from the primary calendar
    # only.
    def insert_friend_meeting(_calendar, meeting, invite:)
      remote = client.post("me/calendar/events", friend_meeting_payload(meeting, attendees: invite))
      { external_event_id: remote["id"], external_ical_uid: remote["iCalUId"] }
    end

    def patch_friend_meeting(row, meeting, attendees:)
      patch_tracked_event(row, row.external_event_id, friend_meeting_payload(meeting, attendees: attendees))
    end

    def delete_friend_meeting(row)
      delete_event(row)
    end

    # The Graph event with the category for the event's color. Without a read of
    # the event (a create or a forced update), the WIT category is set only when
    # the event has a color. After a read, the person's own categories stay and
    # only the WIT category changes.
    def event_payload(data, remote_categories: nil)
      payload  = MicrosoftGraph::EventPayload.build(data)
      category = category_cache.name_for(data[:color_id])

      if remote_categories.nil?
        payload[:categories] = [ category ] if category
      else
        payload.delete(:showAs)
        own = Array(remote_categories).reject { |name| MicrosoftGraph::CategoryCache.app_category?(name) }
        payload[:categories] = own + [ category ].compact
      end

      payload
    end

    def category_cache
      @category_cache ||= MicrosoftGraph::CategoryCache.new(client)
    end

    # The event with only its attendees, or nil when it is gone.
    def fetch_attendees(event_id)
      client.get(event_path(event_id), params: { "$select" => "attendees" })
    rescue MicrosoftGraph::NotFoundError
      nil
    end

    # Returns the id the PATCH reached, or nil when the event is gone.
    def patch_tracked_event(row, event_id, payload)
      client.patch(event_path(event_id), payload)
      event_id
    rescue MicrosoftGraph::NotFoundError
      moved_id = find_event_id_by_ical_uid(row.external_ical_uid)
      return nil if moved_id.blank? || moved_id == event_id

      client.patch(event_path(moved_id), payload)
      moved_id
    end

    def delete_quietly(event_id)
      client.delete(event_path(event_id))
    rescue MicrosoftGraph::NotFoundError
      nil
    end

    def find_event_id_by_ical_uid(ical_uid)
      return nil if ical_uid.blank?

      response = client.get("me/events", params: {
        "$filter" => "iCalUId eq '#{ical_uid.gsub("'", "''")}'",
        "$select" => "id,iCalUId",
        "$top"    => "1"
      })
      response.fetch("value", []).first&.dig("id")
    end

    # Graph cannot take EXDATEs, so each excluded day's occurrence is cancelled
    # once the series exists.
    def cancel_excluded_occurrences(event_id, data)
      MicrosoftGraph::EventPayload.excluded_dates(data[:recurrence]).each do |date|
        day_start = SchoolTimeZone.zone.local(date.year, date.month, date.day)
        response  = client.get("#{event_path(event_id)}/instances", params: {
          "startDateTime" => day_start.iso8601,
          "endDateTime"   => (day_start + 1.day).iso8601,
          "$select"       => "id"
        })

        response.fetch("value", []).each { |occurrence| delete_quietly(occurrence["id"]) }
      end
    end

    # With attendees: true the event lists the invited friends. Without, the
    # key is left out, so a PATCH keeps the attendees that the event has.
    def friend_meeting_payload(meeting, attendees:)
      payload = MicrosoftGraph::EventPayload.build(meeting.event_data)
      return payload unless attendees

      payload[:attendees] = meeting.invitees.map do |friend|
        { emailAddress: { address: friend.email, name: friend.full_name }, type: "required" }
      end
      payload
    end

    def event_path(event_id)
      "me/events/#{escape(event_id)}"
    end

    def escape(id)
      ERB::Util.url_encode(id.to_s)
    end
  end
end
