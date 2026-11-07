# frozen_string_literal: true

module DegreeRequirements
  module PdfCatalog
    # { [subject_code, course_number] => credits } for the courses that the
    # database knows, for a list catalog that prints no credits for most
    # rows (2016-2017 and 2017-2018). ListParser uses a value only for a
    # row the PDF gives no credits for, and only when the semester total
    # that the PDF prints agrees.
    #
    # A course takes the credits of the nearest HTML catalog year that has
    # one value for it, else the credit hours that Banner gives now. The
    # rows of a PDF year are not used: they hold credits that an earlier
    # parser version read or guessed, and an import does not change them.
    module KnownCredits
      module_function

      def call(start_year)
        banner = CatalogCourse.where.not(credit_hours: nil).pluck(:subject_code, :course_number, :credit_hours)
        years = CatalogYearCourse.joins(:catalog_year).where.not(min_credits: nil)
                                 .where("catalog_year_courses.min_credits = catalog_year_courses.max_credits")
                                 .where(catalog_years: { start_year: FIRST_HTML_YEAR.. })
                                 .pluck("catalog_years.start_year", :subject_code, :course_number, :min_credits)
        build(start_year, banner, years)
      end

      # `banner` is [[subject, number, credits], ...] and `years` is
      # [[start_year, subject, number, credits], ...].
      def build(start_year, banner, years)
        credits = banner.to_h { |subject, number, value| [ [ subject, number ], value ] }
        # The nearest year comes last, so its value is the one kept.
        years.sort_by { |year, *| [ -(year - start_year).abs, year ] }
             .each { |_, subject, number, value| credits[[ subject, number ]] = value }
        credits
      end
    end
  end
end
