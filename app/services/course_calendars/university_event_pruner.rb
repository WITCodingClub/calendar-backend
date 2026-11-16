# frozen_string_literal: true

module CourseCalendars
  # Deletes synced university events that the person no longer wants, including
  # past ones. A person who turns off sync_university_events, or who unselects a
  # category, keeps the old events on the calendar without this step, because
  # update_calendar_events never deletes an event that is fully in the past.
  # Holidays stay, because every person gets them.
  class UniversityEventPruner
    attr_reader :user

    def initialize(user)
      @user = user
    end

    def call
      CourseCalendars::Providers.services_for(user).sum { |service| prune_with(service) }
    end

    def prune_with(service)
      course_calendar = service.course_calendar
      return 0 unless course_calendar

      synced = course_calendar.calendar_events.university_events_only.to_a
      return 0 if synced.empty?

      wanted   = wanted_ids(synced.map(&:university_calendar_event_id).uniq).to_set
      unwanted = synced.reject { |event| wanted.include?(event.university_calendar_event_id) }
      return 0 if unwanted.empty?

      service.delete_events(unwanted)
    end

    # The ids, of the given ones, that the person's settings still want
    # (UniversityCalendarEvent.categories_wanted_by, the rule EventBuilder uses).
    def wanted_ids(candidate_ids)
      return [] if candidate_ids.empty?

      UniversityCalendarEvent.where(id: candidate_ids).by_categories(UniversityCalendarEvent.categories_wanted_by(user)).ids
    end
  end
end
