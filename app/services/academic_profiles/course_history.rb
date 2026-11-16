# frozen_string_literal: true

module AcademicProfiles
  # The courses a student took or takes, from their enrollments and the
  # outcomes the extension sent (CourseOutcome). DegreeProgress counts them
  # toward the requirements.
  class CourseHistory
    # A done course first, then one in progress, then one registered for a
    # later term, and one not passed last.
    RANK = { "done" => 0, "in_progress" => 1, "registered" => 2, "not_passed" => 3 }.freeze
    # The statuses of a course that fills a requirement (#1019).
    STATUSES = %w[done in_progress registered].freeze

    # A course the student took or takes. term is the Term. credits are the
    # credit hours of its sections, or nil. status is done, in_progress,
    # registered (a term after the current term, #1019), or not_passed. A
    # transfer credit (#1020) is done, with no term, no CRN,
    # and its source (transcript or student). source is nil for a WIT course.
    Taken = Struct.new(:subject_code, :course_number, :title, :term, :crn, :credits, :status, :outcome, :transfer,
                       :source) do
      def key = [ subject_code, course_number ]
      def code = CourseKeys.format(key)

      def as_json(*)
        { code: code, title: title, term: term&.name, term_uid: term&.uid, crn: crn, credits: credits,
          status: status, outcome: outcome, transfer: transfer || false, source: source }
      end
    end

    def initialize(user, course_keys:, today:)
      @user = user
      @course_keys = course_keys
      @today = today
    end

    # Each course taken at WIT, newest term first, then the transfer credits.
    def taken
      @taken ||= wit_courses + transfer_courses
    end

    # The courses that can meet a requirement: the best attempt of each
    # course (a retake, an old and a new code of one course, or a transfer
    # credit, counts once), without the ones not passed.
    def attempts
      @attempts ||= taken.group_by { |course| @course_keys.equivalents(course.key).min }.values.filter_map { |tries| best_attempt(tries) }
    end

    def current_term
      return @current_term if defined?(@current_term)

      @current_term = Term.current
    end

    private

    # A course taken at WIT wins over a transfer credit for the same course
    # (#1020). The transfer credit counts when no WIT attempt passed, is in
    # progress, or is registered. nil when nothing counts.
    def best_attempt(tries)
      transfer, wit = tries.partition(&:transfer)
      best = wit.min_by { |course| [ RANK.fetch(course.status), -course.term.uid ] }
      best = transfer.first if transfer.any? && (best.nil? || best.status == "not_passed")
      best unless best.status == "not_passed"
    end

    # The AP, test, and transfer credit of the student (#1020), as done
    # courses with no term. A credit with no title or credits takes those of
    # its CatalogCourse (CourseDetails).
    def transfer_courses
      credits = @user.transfer_credits.order(:code).to_a.select(&:key)
      catalog = CourseDetails.new(credits.map(&:key), @course_keys)
      credits.map do |credit|
        subject_code, course_number = credit.key
        details = catalog.for(credit.key)
        Taken.new(subject_code, course_number, credit.title || details[:title] || credit.code, nil, nil,
                  credit.credits || details[:credit_hours], "done", nil, true, credit.source)
      end
    end

    # A lecture and its lab share the code, so the sections of one course in
    # one term are one course: the most credits of a section (as
    # Catalog::ScheduleCheck counts them), and not passed when any section
    # was not passed.
    def wit_courses
      @wit_courses ||= begin
        enrollments = @user.enrollments.includes(course: :term).to_a
        outcomes = CourseOutcome.where(user: @user).to_h { |outcome| [ [ outcome.term_uid, outcome.crn ], outcome.outcome ] }

        # A section stores the subject as Banner's label, "Computer Science
        # (COMP)". The requirements name a course by its subject code.
        sections = enrollments.map(&:course).uniq
                              .group_by { |course| [ course.term_id, Course.prefix_of(course.subject).upcase, course.course_number ] }
        sections.map do |(_, subject_code, _), group|
          section_outcomes = group.to_h { |course| [ course, outcomes[[ course.term.uid, course.crn ]] ] }.compact
          failed = section_outcomes.find { |_, outcome| CourseOutcome::PASSED.exclude?(outcome) }
          course, outcome = failed || section_outcomes.first || [ group.first, nil ]
          Taken.new(subject_code, course.course_number, course.title, course.term, course.crn,
                    group.filter_map(&:credit_hours).max, status(course.term, outcome), outcome)
        end.sort_by { |course| [ -course.term.uid, course.code ] }
      end
    end

    def status(term, outcome)
      return CourseOutcome::PASSED.include?(outcome) ? "done" : "not_passed" if outcome
      return "done" if past?(term)
      return "registered" if later?(term)

      "in_progress"
    end

    # A term after the current term (#1019): a term that has not started.
    # Term.current picks the term by month, so a summer term that started in
    # May is not current yet, and the start date decides first. A term with
    # no start date is later when it is after the current term. With no
    # current term, such a term is not later, so a course keeps in_progress.
    def later?(term)
      return term.start_date > @today if term.start_date

      current_term.present? && term.uid > current_term.uid
    end

    # A term with no end date (an old term) is past when it is before the
    # current term.
    def past?(term)
      return term.end_date < @today if term.end_date

      current_term.present? && term.uid < current_term.uid
    end
  end
end
