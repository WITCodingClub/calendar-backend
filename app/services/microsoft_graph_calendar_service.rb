# frozen_string_literal: true

# Syncs a person's course events to a calendar in their own Microsoft 365
# mailbox through Microsoft Graph. It answers the provider interface that
# CalendarProviders documents, like GoogleCalendarService.
#
# Graph event ids change when an event moves between folders, but iCalUId does
# not. Each tracking row keeps both. When Graph answers 404 for the stored id,
# the service looks the event up by iCalUId, stores the new id and carries on.
# Only when neither id finds the event does it create the event again.
class MicrosoftGraphCalendarService
  include CalendarEventPreparation

  LOCAL_TIME_ZONE = "America/New_York"

  attr_reader :user

  def initialize(user, credential: nil, client: nil)
    @user       = user
    @credential = credential
    @client     = client
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
        # it. The tracking rows point at nothing, so they go too.
        calendar.calendar_events.delete_all
      end
    end

    save_calendar(calendar, create_separate_calendar, placement: "separate")
  end

  # Moves the course events between a calendar of their own and the person's
  # primary calendar. The old events are deleted here. The caller starts a
  # forced sync, which creates them again in the new place. Edits the person
  # made in Outlook do not survive the move.
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
      calendar.calendar_events.delete_all
    else
      delete_tracked_events(calendar)
      # A row that stays points at an event in the primary calendar. After the
      # move, the sync would find that row and update the old event in place.
      # So the move stops here, and the job tries again.
      if calendar.calendar_events.exists?
        raise MicrosoftGraph::Error, "could not delete every course event from the primary calendar"
      end

      remote = create_separate_calendar
    end

    save_calendar(calendar, remote, placement: placement)
  end

  # Removes what the app put in the mailbox: the whole calendar when it is the
  # app's own, or only the tracked events when they are in the primary calendar.
  def remove_course_events(calendar)
    return delete_tracked_events(calendar) if calendar.primary_placement?

    delete_calendar(calendar.external_calendar_id)
  end

  def update_calendar_events(events, force: false)
    calendar = course_calendar
    return empty_stats unless calendar

    existing     = calendar.calendar_events.to_a.index_by { |row| build_event_key(row) }
    current_keys = events.filter_map { |event| build_event_key_from_hash(event) }

    existing.except(*current_keys).each_value do |row|
      delete_remote_event(row) unless event_fully_past?(row)
    end

    stats = upsert_events(calendar, events, existing, force: force)
    calendar.mark_synced!

    Rails.logger.info({ message: "Microsoft calendar sync completed", user_id: user.id, **stats }.to_json)
    stats
  end

  def update_specific_events(events, force: false)
    calendar = course_calendar
    return empty_stats unless calendar

    rows = calendar.calendar_events
    existing = rows.where(meeting_time_id: events.filter_map { |e| e[:meeting_time_id] })
                   .or(rows.where(final_exam_id: events.filter_map { |e| e[:final_exam_id] }))
                   .or(rows.where(university_calendar_event_id: events.filter_map { |e| e[:university_calendar_event_id] }))
                   .index_by { |row| build_event_key(row) }

    upsert_events(calendar, events, existing, force: force)
  end

  def delete_events(db_events)
    db_events = Array(db_events)
    return 0 if db_events.empty? || course_calendar.nil?

    db_events.each { |row| delete_remote_event(row) }
    db_events.size
  end

  # Deletes one remote event. A missing event counts as deleted.
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

  def empty_stats
    { created: 0, updated: 0, skipped: 0 }
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
    client.post("me/calendars", { name: calendar_name })
  end

  def save_calendar(calendar, remote, placement:)
    attributes = {
      external_calendar_id: remote.fetch("id"),
      summary:              remote["name"],
      time_zone:            LOCAL_TIME_ZONE,
      placement:            placement
    }

    if calendar.nil?
      calendar = CourseCalendar.create!(attributes.merge(provider: "microsoft", oauth_credential: credential))
    elsif calendar.external_calendar_id != attributes[:external_calendar_id] || calendar.placement != placement
      calendar.update!(attributes.merge(last_synced_at: nil))
    end

    calendar.external_calendar_id
  end

  # One failed delete must not stop the others, so it is logged and the row
  # stays. A row that stays is tried again on the next call.
  def delete_tracked_events(calendar)
    calendar.calendar_events.find_each do |row|
      delete_remote_event(row)
    rescue MicrosoftGraph::Error => e
      Rails.logger.error({ message: "Could not delete a Microsoft event", user_id: user&.id,
                           calendar_event_id: row.id, error: e.class.name }.to_json)
    end
  end

  def upsert_events(calendar, events, existing, force:)
    resolver = PreferenceResolver.new(user)
    renderer = CalendarTemplateRenderer.new
    stats    = empty_stats

    events.each do |event|
      row  = existing[build_event_key_from_hash(event)]
      data = apply_preferences_to_event(resolve_syncable(event), event,
                                        preference_resolver: resolver, template_renderer: renderer)

      if row.nil?
        create_remote_event(calendar, event, data)
        stats[:created] += 1
      elsif force || row.data_changed?(data)
        result = update_remote_event(calendar, row, event, data, force: force)
        stats[result == :skipped_user_edit ? :skipped : :updated] += 1
      else
        row.mark_synced!
        stats[:skipped] += 1
      end
    end

    stats
  end

  def create_remote_event(calendar, event, data)
    remote = client.post("me/calendars/#{escape(calendar.external_calendar_id)}/events", event_payload(data))
    cancel_excluded_occurrences(remote.fetch("id"), data)

    calendar.calendar_events.create!(
      row_attributes(data)
        .merge(syncable_ids(event))
        .merge(external_event_id: remote["id"], external_ical_uid: remote["iCalUId"])
    )
  rescue ActiveRecord::RecordNotUnique
    # A concurrent sync already tracks this event, so the one just created is a
    # duplicate. Remove it rather than leave it on the calendar.
    delete_quietly(remote["id"]) if remote
    nil
  end

  # Like GoogleCalendarService#update_event_in_calendar: without force, the
  # service reads the Outlook event first and keeps each field the person
  # changed there. A changed recurrence keeps the whole event. A forced sync
  # writes the app's values and forgets the edits.
  def update_remote_event(calendar, row, event, data, force:)
    event_id = row.external_event_id
    edited   = []
    remote   = nil
    payload_data = data

    unless force
      event_id, remote = fetch_tracked_event(row)
      return recreate_remote_event(calendar, row, event, data) if event_id.blank?

      edits = MicrosoftGraph::EventEdits.new(row, remote)
      return keep_recurrence_edit(row, event_id, edits) if edits.recurrence_changed?

      edited       = ((row.user_edited_fields || []) + edits.edited_fields).uniq
      payload_data = edits.merge(data, edited)
    end

    payload  = event_payload(payload_data, remote_categories: remote&.fetch("categories", nil))
    event_id = patch_event(row, event_id, payload)
    return recreate_remote_event(calendar, row, event, data) if event_id.blank?

    cancel_excluded_occurrences(event_id, payload_data)
    row.update!(row_attributes(payload_data).merge(external_event_id: event_id, user_edited_fields: edited.presence))
    :updated
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
      # After a read, the person's own free or busy choice stays.
      payload.delete(:showAs)
      own = Array(remote_categories).reject { |name| MicrosoftGraph::CategoryCache.app_category?(name) }
      payload[:categories] = own + [ category ].compact
    end

    payload
  end

  def category_cache
    @category_cache ||= MicrosoftGraph::CategoryCache.new(client)
  end

  # Returns the event id and the event. The id is nil when neither the stored
  # id nor the iCalUId finds the event.
  def fetch_tracked_event(row)
    [ row.external_event_id, fetch_event(row.external_event_id) ]
  rescue MicrosoftGraph::NotFoundError
    moved_id = find_event_id_by_ical_uid(row.external_ical_uid)
    return [ nil, nil ] if moved_id.blank?

    begin
      [ moved_id, fetch_event(moved_id) ]
    rescue MicrosoftGraph::NotFoundError
      [ nil, nil ]
    end
  end

  def fetch_event(event_id)
    client.get(event_path(event_id), params: { "$select" => MicrosoftGraph::EventEdits::SELECT })
  end

  # Returns the id the PATCH reached, or nil when the event is gone.
  def patch_event(row, event_id, payload)
    client.patch(event_path(event_id), payload)
    event_id
  rescue MicrosoftGraph::NotFoundError
    moved_id = find_event_id_by_ical_uid(row.external_ical_uid)
    return nil if moved_id.blank? || moved_id == event_id

    client.patch(event_path(moved_id), payload)
    moved_id
  end

  # The person changed the recurrence in Outlook. The app cannot merge a
  # series, so it keeps the event and records what the person left.
  def keep_recurrence_edit(row, event_id, edits)
    Rails.logger.info({ message: "Microsoft event recurrence edited in Outlook, keeping it", user_id: user.id, calendar_event_id: row.id }.to_json)
    attributes = edits.remote_attributes
    row.update!(attributes.merge(
      external_event_id: event_id,
      event_data_hash:   CalendarEvent.generate_data_hash(attributes.merge(recurrence: row.recurrence)),
      last_synced_at:    Time.current
    ))
    :skipped_user_edit
  end

  def recreate_remote_event(calendar, row, event, data)
    Rails.logger.warn({ message: "Microsoft event not found, recreating", user_id: user.id, calendar_event_id: row.id }.to_json)
    row.skip_remote_deletion = true
    row.destroy!
    create_remote_event(calendar, event, data)
  end

  def delete_remote_event(row)
    delete_calendar_event(row.external_event_id, row.external_ical_uid)
    row.skip_remote_deletion = true
    row.destroy
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
  # once the series exists. Updating a series restores its occurrences, so this
  # runs after every create and update.
  def cancel_excluded_occurrences(event_id, data)
    zone = Time.find_zone!(LOCAL_TIME_ZONE)

    MicrosoftGraph::EventPayload.excluded_dates(data[:recurrence]).each do |date|
      day_start = zone.local(date.year, date.month, date.day)
      response  = client.get("#{event_path(event_id)}/instances", params: {
        "startDateTime" => day_start.iso8601,
        "endDateTime"   => (day_start + 1.day).iso8601,
        "$select"       => "id"
      })

      response.fetch("value", []).each { |occurrence| delete_quietly(occurrence["id"]) }
    end
  end

  def row_attributes(data)
    {
      summary:         data[:summary],
      location:        data[:location],
      start_time:      data[:start_time],
      end_time:        data[:end_time],
      recurrence:      data[:recurrence],
      event_data_hash: CalendarEvent.generate_data_hash(data),
      last_synced_at:  Time.current
    }
  end

  def syncable_ids(event)
    event.slice(:meeting_time_id, :final_exam_id, :university_calendar_event_id).compact.first(1).to_h
  end

  def event_path(event_id)
    "me/events/#{escape(event_id)}"
  end

  def escape(id)
    ERB::Util.url_encode(id.to_s)
  end

  def calendar_name
    prefix = { "test" => "[TEST] ", "development" => "[DEV] ", "stage" => "[STAGE] " }[Rails.env] || ""
    "#{prefix}WIT Courses"
  end
end
