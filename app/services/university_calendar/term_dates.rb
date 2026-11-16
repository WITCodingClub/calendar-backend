# frozen_string_literal: true

module UniversityCalendar
  # The dates of a term from LeopardWeb and the university calendar.
  # UniversityCalendar::SyncJob fills the dates that a term does not have yet.
  # A term's courses win over these dates (see Term).
  module TermDates
    # - start_date: the day LeopardWeb first lists the term (registration
    #   opens), kept once it is in the past. Else the "course schedule
    #   available" event, else 14 days before the registration event.
    # - end_date: the last day of the finals period, else the last course end.
    #
    # Both dates must fall inside Term.date_window, and the end date in the
    # term's own year. Without this, Summer 2027 took 2026-07-25 (the day
    # LeopardWeb first listed it) and the Summer 2026 finals end (2026-08-11).
    #
    # Returns { start_date:, end_date: }, each nil when no source gives one.
    def self.detect(year, season)
      term = Term.find_by(year: year, season: season)

      window = Term.date_window(year, season)
      candidate_events = UniversityCalendarEvent.where(start_time: window.first.beginning_of_day..window.last.end_of_day)
      matching_events = candidate_events.select { |event| event_matches_term_for_date_detection?(event, year, season, term) }

      leopard_web_start_date = leopard_web_registration_open_date(year, season, term)
      leopard_web_start_date = nil unless leopard_web_start_date&.in?(window)

      schedule_available_event = matching_events
                                 .select { |event| schedule_available_summary?(event.summary) }
                                 .min_by(&:start_time)

      registration_event = matching_events
                           .select { |event| registration_summary?(event.summary) }
                           .min_by(&:start_time)
      estimated_schedule_available_date = registration_event&.start_time&.to_date&.-(14)

      finals_period_event = matching_events
                            .select { |event| event.category == "finals" && finals_period_summary?(event.summary) }
                            .max_by { |event| event.end_time || event.start_time }

      finals_end_date = finals_period_event&.end_time&.to_date || finals_period_event&.start_time&.to_date
      course_end_fallback = term&.course_dates&.last

      start_date = leopard_web_start_date || schedule_available_event&.start_time&.to_date || estimated_schedule_available_date
      end_date   = finals_end_date || course_end_fallback

      {
        start_date: (start_date if start_date&.in?(window)),
        end_date:   (end_date if Term.plausible_end_date?(end_date, year, window))
      }
    end

    def self.leopard_web_registration_open_date(year, season, term)
      target_uid = term&.uid || TermCode.for(year, season)
      return nil unless target_uid

      active_term_found = Catalog::LeopardWebClient.get_active_terms.any? { |active_term| active_term[:code].to_i == target_uid }
      return nil unless active_term_found

      existing_start_date = term&.start_date
      return existing_start_date if existing_start_date.present? && existing_start_date <= Time.zone.today

      Time.zone.today
    rescue => e
      Rails.error.report(e, handled: true, context: { year: year, season: season.to_s })
      nil
    end

    def self.event_matches_term_for_date_detection?(event, year, season, term)
      season_name = season.to_s.capitalize
      summary = event.summary.to_s
      academic_term = event.academic_term.to_s

      named_term = TermCode.find_in(summary)
      return named_term == TermCode.for(year, season) if named_term

      return true if term && event.term_id == term.id
      return true if summary.match?(/\b#{Regexp.escape(season_name)}\b/i) && summary.match?(/\b#{year}\b/)

      return false unless academic_term.match?(/\b#{Regexp.escape(season_name)}\b/i)

      event_date = event.start_time&.to_date
      return false unless event_date

      event_date.in?(Term.date_window(year, season))
    end

    def self.schedule_available_summary?(summary)
      summary = summary.to_s
      return false if registration_summary?(summary)

      summary.match?(/course\s+schedule/i) ||
        summary.match?(/schedule\s+(available|release|released|posted|opens|open|begins|begin)/i)
    end

    # The feed has no registration category of its own: "registration" also
    # holds add/drop and enrollment deadlines.
    def self.registration_summary?(summary)
      summary.to_s.match?(/registration/i)
    end

    # Wider than UniversityCalendarEvent.finals_periods, which decides the
    # days with no classes: any finals event that is not a schedule release
    # can end the term.
    def self.finals_period_summary?(summary)
      summary = summary.to_s
      return false if summary.match?(/schedule\s+(available|online|release|released|posted)/i)

      summary.match?(/final\s+exam\s+period|final\s+exams?|finals\s+week|examination\s+period|study\s+day/i)
    end

    # Fills each date the term does not have with the detected one. Returns the
    # dates it wrote.
    def self.fill_missing(term)
      detected = detect(term.year, term.season)
      updates = detected.select { |field, value| value && term[field].nil? }
      term.update!(updates) if updates.any?
      updates
    end
  end
end
