# frozen_string_literal: true

module DegreeRequirements
  # Compares the courses of one catalog year (CatalogYearCourse, from the
  # course search API of the catalog site) with Banner's CatalogCourse rows.
  # The admin report of #864 shows the four lists.
  #
  #   catalog_only    the catalog year prints the code, Banner does not know it
  #   banner_only     Banner has sections of the code in a term of the catalog
  #                   year, and the catalog year does not print it
  #   title_differs   both have the code, with a different title
  #   credits_differ  both have the code, and Banner's credits are outside
  #                   the catalog's range
  #
  # Titles are compared without case, punctuation, or spaces, because Banner
  # and the catalog format them differently (COMP 1000 "COMPUTER SCIENCE I"
  # and "Computer Science I" are the same).
  class CourseComparison
    KINDS = %i[catalog_only banner_only title_differs credits_differ].freeze

    # The join of a catalog year course and a Banner course with the same code.
    SAME_CODE = "catalog_courses.subject_code = catalog_year_courses.subject_code " \
                "AND catalog_courses.course_number = catalog_year_courses.course_number"

    Row = Data.define(:code, :catalog_title, :banner_title, :catalog_credits, :banner_credits)

    attr_reader :catalog_year

    def initialize(catalog_year)
      @catalog_year = catalog_year
    end

    def rows(kind)
      raise ArgumentError, "unknown kind #{kind.inspect}" unless KINDS.include?(kind)

      public_send(kind)
    end

    def counts
      KINDS.index_with { |kind| rows(kind).size }
    end

    def catalog_only
      @catalog_only ||= catalog_year.catalog_year_courses
                                    .where.not(CatalogCourse.where(SAME_CODE).arel.exists)
                                    .order(:subject_code, :course_number)
                                    .map { |course| row(course, nil) }
    end

    def banner_only
      @banner_only ||= begin
        codes = codes_offered_in_year - catalog_year.catalog_year_courses.pluck(:subject_code, :course_number)
        if codes.empty?
          []
        else
          CatalogCourse.where(subject_code: codes.map(&:first).uniq, course_number: codes.map(&:last).uniq)
                       .select { |course| codes.include?([ course.subject_code, course.course_number ]) }
                       .sort_by { |course| [ course.subject_code, course.course_number ] }
                       .map { |course| row(nil, course) }
        end
      end
    end

    def title_differs
      @title_differs ||= pairs.select do |catalog, banner|
        catalog.title.present? && banner.title.present? && normalize(catalog.title) != normalize(banner.title)
      end.map { |catalog, banner| row(catalog, banner) }
    end

    def credits_differ
      @credits_differ ||= pairs.select do |catalog, banner|
        next false if catalog.min_credits.nil? || banner.credit_hours.nil?

        !(catalog.min_credits..(catalog.max_credits || catalog.min_credits)).cover?(banner.credit_hours)
      end.map { |catalog, banner| row(catalog, banner) }
    end

    private

    # Each catalog year course with the Banner course of the same code.
    def pairs
      @pairs ||= begin
        year_courses = catalog_year.catalog_year_courses.order(:subject_code, :course_number).to_a
        banner = CatalogCourse.where(subject_code: year_courses.map(&:subject_code).uniq,
                                     course_number: year_courses.map(&:course_number).uniq)
                              .index_by { |course| [ course.subject_code, course.course_number ] }
        year_courses.filter_map do |course|
          match = banner[[ course.subject_code, course.course_number ]]
          [ course, match ] if match
        end
      end
    end

    # The codes of the Banner sections in the fall, spring, and summer terms
    # of the catalog year (CatalogYear.start_year_for). A section stores its
    # subject as Banner labels it, "Computer Science (COMP)", so the code is
    # read from the label the same way CatalogCourse rows get it.
    def codes_offered_in_year
      start_year = catalog_year.start_year
      terms = Term.where(year: start_year, season: :fall).or(Term.where(year: start_year + 1, season: %i[spring summer]))
      Course.where(term_id: terms.select(:id)).distinct.pluck(:subject, :course_number)
            .to_set { |subject, number| [ Catalog::CourseDetailsSync.prefix_of(subject), number ] }
    end

    def normalize(title)
      title.downcase.gsub("&", " and ").gsub(/[^a-z0-9]+/, " ").squish
    end

    def row(catalog, banner)
      Row.new(code: (catalog || banner).code,
              catalog_title: catalog&.title,
              banner_title: banner&.title,
              catalog_credits: catalog && credits(catalog.min_credits, catalog.max_credits),
              banner_credits: banner&.credit_hours)
    end

    def credits(min, max)
      return nil if min.nil?

      max.nil? || max == min ? min.to_s : "#{min}-#{max}"
    end
  end
end
