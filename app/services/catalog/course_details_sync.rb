# frozen_string_literal: true

module Catalog
  # Fetches Banner's description, prerequisites, corequisites, and
  # restrictions for each course in one term, and stores them on its
  # CatalogCourse. Banner gives these per section, but they belong to the
  # course, so one section of each course is enough.
  #
  # The newest term wins. A course is skipped when its details came from a
  # newer term, or from this term less than FRESH_FOR ago, so a backfill of
  # old terms only fills the gaps.
  #
  # A failed fetch keeps the old details and is reported. The sync goes on with
  # the next course.
  class CourseDetailsSync
    FRESH_FOR = 7.days
    PAUSE     = 0.1

    Result = Data.define(:fetched, :skipped, :failed)

    def initialize(term, client: LeopardWebClient, pause: PAUSE)
      @term   = term
      @client = client
      @pause  = pause
    end

    # Makes sure every course in the sections has a CatalogCourse, with the
    # title of its newest section. Links prerequisite rows that named a course
    # before it had a row. Sends no request to Banner.
    def self.seed(sections)
      rows = sections.joins(:term).order("terms.uid": :desc)
                     .pluck(:subject, :course_number, :title)
                     .uniq { |subject, number, _| [ prefix_of(subject), number ] }
      return 0 if rows.empty?

      now = Time.current
      inserted = CatalogCourse.insert_all(
        rows.map do |subject, number, title|
          { subject_code: prefix_of(subject), course_number: number, title: title, created_at: now, updated_at: now }
        end,
        unique_by: %i[subject_code course_number]
      )
      link_orphan_prerequisites
      link_degree_requirements if inserted.length.positive?
      rows.size
    end

    def self.prefix_of(subject)
      (subject.to_s[/\(([^)]+)\)\s*\z/, 1] || subject.to_s).strip.upcase
    end

    # The degree requirements and the term elective lists name courses by
    # code. A course that Banner lists for the first time gets its links here
    # (docs/degree-requirements.md, docs/term-electives.md).
    def self.link_degree_requirements
      [ ProgramPlanItem, ElectiveGroupCourse, CatalogYearCourse, TermElectiveCourse ].each(&:link_catalog_courses)
    end

    def self.link_orphan_prerequisites
      CoursePrerequisite.where(required_catalog_course_id: nil)
                        .joins("JOIN catalog_courses ON catalog_courses.subject_code = course_prerequisites.required_subject_code " \
                               "AND catalog_courses.course_number = course_prerequisites.required_course_number")
                        .update_all("required_catalog_course_id = catalog_courses.id")
    end

    def call
      self.class.seed(@term.courses)

      fetched = skipped = failed = 0
      one_section_per_course.each do |subject_code, course_number, crn|
        catalog_course = CatalogCourse.find_by!(subject_code: subject_code, course_number: course_number)
        if fresh?(catalog_course)
          skipped += 1
          next
        end

        if store(catalog_course, crn)
          fetched += 1
        else
          failed += 1
        end
        sleep @pause if @pause.positive?
      end

      Result.new(fetched: fetched, skipped: skipped, failed: failed)
    end

    private

    # [subject_code, course_number, crn] with the lowest CRN of each course.
    def one_section_per_course
      @term.courses.order(:crn).pluck(:subject, :course_number, :crn)
           .map { |subject, number, crn| [ self.class.prefix_of(subject), number, crn ] }
           .uniq { |code, number, _| [ code, number ] }
    end

    def fresh?(catalog_course)
      source = catalog_course.source_term
      return false if source.nil? || catalog_course.details_fetched_at.nil?
      return true if source.uid > @term.uid

      source.uid == @term.uid && catalog_course.details_fetched_at > FRESH_FOR.ago
    end

    def store(catalog_course, crn)
      pages = @client.get_course_details(term: @term.uid, course_reference_number: crn)
      details = CourseDetailsParser.description(pages[:description])
      prerequisites = CourseDetailsParser.prerequisites(pages[:prerequisites])

      CatalogCourse.transaction do
        catalog_course.update!(
          description:        details[:description],
          credit_hours:       details[:credit_hours] || catalog_course.credit_hours,
          typically_offered:  details[:typically_offered],
          prerequisites:      prerequisites,
          corequisites:       CourseDetailsParser.corequisites(pages[:corequisites]),
          restrictions:       CourseDetailsParser.restrictions(pages[:restrictions]),
          source_term:        @term,
          details_fetched_at: Time.current
        )
        replace_prerequisite_links(catalog_course, prerequisites)
      end
      true
    rescue LeopardWebClient::RequestError, Faraday::Error => e
      Rails.error.report(e, handled: true, context: { catalog_course_id: catalog_course.id, term_uid: @term.uid, crn: crn })
      false
    end

    def replace_prerequisite_links(catalog_course, tree)
      catalog_course.course_prerequisites.delete_all
      leaves = course_leaves(tree).uniq { |leaf| [ leaf["subject_code"], leaf["course_number"] ] }
      return if leaves.empty?

      ids = CatalogCourse.where(subject_code: leaves.map { |leaf| leaf["subject_code"] }.uniq)
                         .pluck(:subject_code, :course_number, :id)
                         .to_h { |code, number, id| [ [ code, number ], id ] }
      now = Time.current
      CoursePrerequisite.insert_all!(
        leaves.map do |leaf|
          {
            catalog_course_id:          catalog_course.id,
            required_catalog_course_id: ids[[ leaf["subject_code"], leaf["course_number"] ]],
            required_subject_code:      leaf["subject_code"],
            required_course_number:     leaf["course_number"],
            min_grade:                  leaf["min_grade"],
            created_at:                 now,
            updated_at:                 now
          }
        end
      )
    end

    def course_leaves(node)
      return [] if node.nil?
      return [ node ] if node["type"] == "course"

      Array(node["operands"]).flat_map { |operand| course_leaves(operand) }
    end
  end
end
