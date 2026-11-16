# frozen_string_literal: true

module UniversityCalendar
  # Finds the start and end dates of a term from the university calendar, the
  # terms that LeopardWeb lists, and the term's courses. UniversityCalendar::SyncJob
  # fills the dates that a term does not have yet.
  module TermDates
    # Date rules:
    # - start_date: The day LeopardWeb reports registration open for the term.
    #               Once captured, keep the stored past start_date stable across
    #               later syncs.
    # - end_date:   Last day of finals period for the term.
    #               Falls back to latest imported course end_date for the term
    #               when finals period events are unavailable.
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
      course_end_fallback = fallback_end_date_from_courses(term)

      start_date = leopard_web_start_date || schedule_available_event&.start_time&.to_date || estimated_schedule_available_date
      end_date   = finals_end_date || course_end_fallback

      {
        start_date: (start_date if start_date&.in?(window)),
        end_date:   (end_date if Term.plausible_end_date?(end_date, year, window))
      }
    end

    def self.leopard_web_registration_open_date(year, season, term)
      result = Catalog::LeopardWebClient.get_active_terms
      return nil unless result[:success]

      target_uid = term&.uid || TermCode.for(year, season)
      return nil unless target_uid

      active_term_found = Array(result[:terms]).any? do |active_term|
        (active_term[:code] || active_term["code"]).to_i == target_uid
      end
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

      explicit_summary_term = extract_explicit_term_from_summary(summary)
      if explicit_summary_term
        return explicit_summary_term[:season] == season.to_sym && explicit_summary_term[:year] == year
      end

      return true if term && event.term_id == term.id
      return true if summary.match?(/\b#{Regexp.escape(season_name)}\b/i) && summary.match?(/\b#{year}\b/)

      return false unless academic_term.match?(/\b#{Regexp.escape(season_name)}\b/i)

      event_date = event.start_time&.to_date
      return false unless event_date

      event_date.in?(Term.date_window(year, season))
    end

    def self.extract_explicit_term_from_summary(summary)
      match = summary.to_s.match(/\b(Fall|Spring|Summer)\s+(\d{4})\b/i)
      return nil unless match

      season = case match[1].downcase
      when "fall" then :fall
      when "spring" then :spring
      when "summer" then :summer
      end

      return nil unless season

      { season: season, year: match[2].to_i }
    end

    def self.schedule_available_summary?(summary)
      normalized = summary.to_s
      return false if registration_summary?(normalized)

      normalized.match?(/course\s+schedule/i) ||
        normalized.match?(/schedule\s+(available|release|released|posted|opens|open|begins|begin)/i)
    end

    def self.registration_summary?(summary)
      summary.to_s.match?(/registration\s+(opens|open|begins|begin)|registration/i)
    end

    def self.finals_period_summary?(summary)
      normalized = summary.to_s
      return false if normalized.match?(/schedule\s+(available|online|release|released|posted)/i)

      normalized.match?(/final\s+exam\s+period|final\s+exams?|finals\s+week|examination\s+period|study\s+day/i)
    end

    def self.fallback_end_date_from_courses(term)
      return nil unless term

      term.courses.where.not(start_date: nil)
          .where.not(end_date: nil)
          .where("EXTRACT(YEAR FROM start_date) >= ? AND EXTRACT(YEAR FROM start_date) <= ?", term.year - 1, term.year)
          .where("EXTRACT(YEAR FROM end_date) >= ? AND EXTRACT(YEAR FROM end_date) <= ?", term.year, term.year + 1)
          .maximum(:end_date)
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
