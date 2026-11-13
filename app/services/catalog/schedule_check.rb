# frozen_string_literal: true

module Catalog
  # Checks a set of sections that a student wants to register for together:
  # time conflicts, linked lecture and lab pairs, the same course twice, and
  # totals for the week.
  #
  #   Catalog::ScheduleCheck.new(term_uid: 202720, crns: [ 20397, 20401 ]).call
  #
  # Linked sections: Banner's own pairs (Catalog::SectionLinks, source
  # "banner") once they are fetched, else the link identifier guess.
  #
  # Catalog::ScheduleRules has the rules and the totals, which
  # Catalog::ScheduleOptions shares.
  class ScheduleCheck
    class TermNotFoundError < ::Catalog::FilterError; end

    MAX_CRNS = 30
    EARLY_START = ScheduleRules::EARLY_START

    DAYS = ScheduleRules::DAYS

    def initialize(term_uid:, crns:)
      @term_uid = term_uid
      @crns     = Array(crns).map(&:to_i).uniq
    end

    def call
      raise FilterError, "Give at least one CRN" if @crns.empty?
      raise FilterError, "Give at most #{MAX_CRNS} CRNs" if @crns.size > MAX_CRNS

      {
        term:            { uid: term.uid, name: term.name },
        sections:        sections.map { |course| section_json(course) },
        not_found:       @crns - found.map(&:crn),
        cancelled:       cancelled.map(&:crn),
        conflicts:       conflicts,
        link_problems:   link_problems,
        duplicates:      duplicates,
        totals:          totals
      }
    end

    private

    def term
      @term ||= Term.find_by(uid: @term_uid) || raise(TermNotFoundError, "Unknown term_uid #{@term_uid.inspect}")
    end

    def found
      @found ||= Course.where(term: term, crn: @crns)
                       .includes({ section_links: :linked_course }, meeting_times: { rooms: :building })
                       .sort_by { |course| @crns.index(course.crn) }
    end

    def sections
      @sections ||= found.select(&:active?)
    end

    def cancelled
      found.reject(&:active?)
    end

    def code(course)
      SectionSerializer.course_code_for(course)
    end

    def section_json(course)
      {
        crn:           course.crn,
        course_code:   code(course),
        title:         course.title,
        schedule_type: course.schedule_type,
        credit_hours:  course.credit_hours,
        meeting_times: meetings(course).map { |mt| MeetingTimeSerializer.new(mt).as_json.slice(:day, :begin_time, :end_time) }
      }
    end

    def meetings(course) = ScheduleRules.meetings(course)

    # Two sections conflict when they meet on the same day at overlapping
    # times, during overlapping dates. Half-term sections in different halves
    # do not conflict.
    def conflicts
      sections.combination(2).flat_map do |a, b|
        meetings(a).product(meetings(b)).filter_map do |x, y|
          next unless ScheduleRules.overlap?(x, y)

          {
            crns:  [ a.crn, b.crn ],
            day:   x.day_of_week,
            times: [ "#{x.fmt_begin_time_military}-#{x.fmt_end_time_military}",
                     "#{y.fmt_begin_time_military}-#{y.fmt_end_time_military}" ]
          }
        end
      end
    end

    # A linked section needs every section of one of its option groups.
    def link_problems
      chosen = sections.map(&:crn)

      sections.filter_map do |course|
        links = SectionLinks.new(course)
        next unless links.required?

        next if links.met_by?(chosen)

        groups = links.options.map { |group| group.map(&:crn) }
        link_problem(course, links, groups)
      end
    end

    def link_problem(course, links, groups)
      base = { crn: course.crn, source: links.banner? ? "banner" : "link_identifier",
               partner_crns: groups.flatten.uniq, partner_options: groups }

      if groups.empty?
        base.merge(problem: "unverified_link",
                   message: "#{code(course)} (#{course.crn}) is marked as linked, but Banner's pairs are not " \
                            "stored yet and its link identifier names no partner. Check it in LeopardWeb.")
      else
        choices = groups.map { |group| group.join(" + ") }.join(", or ")
        base.merge(problem: "missing_partner",
                   message: "#{code(course)} (#{course.crn}) must be taken with #{choices}.")
      end
    end

    # The same course twice, other than a linked lecture and lab.
    def duplicates
      sections.group_by { |course| ScheduleRules.duplicate_key(course) }
              .select { |_key, group| group.size > 1 }
              .map do |_key, group|
                { course_code: code(group.first).split("-").first, crns: group.map(&:crn) }
              end
    end

    def totals = ScheduleRules.totals(sections)
  end
end
