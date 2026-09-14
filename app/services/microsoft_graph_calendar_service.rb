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

  def create_or_get_course_calendar
    raise MicrosoftGraph::AuthError, "No Microsoft credential found for user" unless credential

    calendar = course_calendar

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

    remote = client.post("me/calendars", { name: calendar_name })
    attributes = {
      external_calendar_id: remote.fetch("id"),
      summary:              remote["name"],
      time_zone:            LOCAL_TIME_ZONE,
      last_synced_at:       nil
    }

    if calendar
      calendar.update!(attributes)
    else
      calendar = CourseCalendar.create!(attributes.merge(provider: "microsoft", oauth_credential: credential))
    end

    calendar.external_calendar_id
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

  def delete_calendar(calendar_id)
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
        update_remote_event(calendar, row, event, data)
        stats[:updated] += 1
      else
        row.mark_synced!
        stats[:skipped] += 1
      end
    end

    stats
  end

  def create_remote_event(calendar, event, data)
    remote = client.post("me/calendars/#{escape(calendar.external_calendar_id)}/events",
                         MicrosoftGraph::EventPayload.build(data))
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

  def update_remote_event(calendar, row, event, data)
    payload  = MicrosoftGraph::EventPayload.build(data)
    event_id = row.external_event_id

    begin
      client.patch(event_path(event_id), payload)
    rescue MicrosoftGraph::NotFoundError
      event_id = find_event_id_by_ical_uid(row.external_ical_uid)
      return recreate_remote_event(calendar, row, event, data) if event_id.blank?

      client.patch(event_path(event_id), payload)
    end

    cancel_excluded_occurrences(event_id, data)
    row.update!(row_attributes(data).merge(external_event_id: event_id))
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
