# frozen_string_literal: true

module CourseCalendars
  class IcsFeed
    # University events in the dates of the user's terms: every holiday, and
    # the categories the user chose to sync.
    class UniversityEvents
      def initialize(user, courses, preference_resolver)
        @user                = user
        @courses             = courses
        @preference_resolver = preference_resolver
      end

      def append_to(cal)
        enrolled_term_ids = @courses.map(&:term_id).compact.uniq
        return if enrolled_term_ids.empty?

        min_date, max_date = date_range_for_terms(enrolled_term_ids)
        if min_date && max_date
          UniversityCalendarEvent.holidays.in_date_range(min_date, max_date).find_each do |event|
            add_event(cal, event, force_all_day: true)
          end
        end

        user_config = @user.user_extension_config
        return unless user_config&.sync_university_events

        categories = user_config.synced_university_event_categories
        return if categories.empty?

        if min_date && max_date
          UniversityCalendarEvent.by_categories(categories).in_date_range(min_date, max_date).find_each do |event|
            add_event(cal, event)
          end
        end
      end

      private

      # Returns [min_date, max_date] for the holiday query range.
      # Prefers term start/end dates; falls back to meeting time dates when terms
      # lack end_date (e.g. Fall 2026 before finals are scheduled).
      def date_range_for_terms(enrolled_term_ids)
        terms = Term.where(id: enrolled_term_ids).where.not(start_date: nil).where.not(end_date: nil)
        if terms.any?
          return [ terms.minimum(:start_date), terms.maximum(:end_date) ]
        end

        meeting_times = @courses.flat_map { |c| c.meeting_times.to_a }
        min = meeting_times.filter_map(&:start_date).min
        max = meeting_times.filter_map(&:end_date).max
        [ min, max ]
      end

      def add_event(cal, event, force_all_day: false)
        cal.event do |e|
          is_all_day = force_all_day || event.all_day || event.category == "holiday"

          if is_all_day
            e.dtstart = Icalendar::Values::Date.new(event.start_time.to_date)
            e.dtend   = Icalendar::Values::Date.new(event.end_time.to_date + 1.day)
          else
            e.dtstart = Icalendar::Values::DateTime.new(event.start_time, tzid: TZID)
            e.dtend   = Icalendar::Values::DateTime.new(event.end_time,   tzid: TZID)
          end

          e.summary     = event.category == "holiday" ? event.formatted_holiday_summary : event.summary
          e.description = event.description if event.description.present?
          e.location    = event.location    if event.location.present?
          e.uid         = "university-#{event.ics_uid}@calendar-util.wit.edu"
          e.dtstamp     = Icalendar::Values::DateTime.new(event.updated_at, tzid: TZID)
          e.last_modified = Icalendar::Values::DateTime.new(event.updated_at, tzid: TZID)
          e.sequence    = (event.updated_at.to_i / 60)
          e.categories  = [ event.category.titleize ] if event.category.present?

          # The same color the Google and Outlook sync gives the event.
          color_hex = GoogleCalendar::Colors.normalize(@preference_resolver.resolve_for(event)[:color_id])
          if color_hex
            e.color = color_hex
            e.append_custom_property("X-APPLE-CALENDAR-COLOR", color_hex)
          end

          if event.category == "holiday"
            e.append_custom_property("X-MICROSOFT-CDO-ALLDAYEVENT", "TRUE")
            e.append_custom_property("X-MICROSOFT-CDO-BUSYSTATUS", "FREE")
            e.transp = "TRANSPARENT"
          end
        end
      end
    end
  end
end
