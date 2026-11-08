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
    # one value for it, else the credit hours that Banner gives now, else
    # the credits of the nearest grid year (2013-2015) plan that prints it.
    # The grid plans come last: they fill courses that closed before 2019,
    # and a course can change credits between a grid year and 2019. The
    # catalog year courses of a PDF year are not used: they hold credits
    # that an earlier parser version read or guessed, and an import does
    # not change them.
    module KnownCredits
      GRID_YEARS = LAYOUTS.select { |_, layout| layout == :grid }.keys.freeze

      module_function

      def call(start_year)
        banner = CatalogCourse.where.not(credit_hours: nil).pluck(:subject_code, :course_number, :credit_hours)
        years = CatalogYearCourse.joins(:catalog_year).where.not(min_credits: nil)
                                 .where("catalog_year_courses.min_credits = catalog_year_courses.max_credits")
                                 .where(catalog_years: { start_year: FIRST_HTML_YEAR.. })
                                 .pluck("catalog_years.start_year", :subject_code, :course_number, :min_credits)
        build(start_year, banner, years, unanimous(grid_plan_rows))
      end

      # [[start_year, subject, number, credits], ...] of the course rows in
      # the stored plans of the grid years.
      def grid_plan_rows
        ProgramPlanItem.joins(program_plan: { requirement_set: :catalog_year })
                       .where(catalog_years: { start_year: GRID_YEARS }, kind: "course")
                       .where("program_plan_items.min_credits = program_plan_items.max_credits")
                       .distinct.pluck("catalog_years.start_year", :subject_code, :course_number, :min_credits)
      end

      # The rows of a course that has one value in its year.
      def unanimous(rows)
        rows.group_by { |year, subject, number, _| [ year, subject, number ] }
            .filter_map { |_, same| same.first if same.map(&:last).uniq.size == 1 }
      end

      # `banner` is [[subject, number, credits], ...], and `years` and
      # `grid` are [[start_year, subject, number, credits], ...].
      def build(start_year, banner, years, grid = [])
        nearest(start_year, grid)
          .merge(banner.to_h { |subject, number, value| [ [ subject, number ], value ] })
          .merge(nearest(start_year, years))
      end

      def nearest(start_year, rows)
        # The nearest year comes last, so its value is the one kept.
        rows.sort_by { |year, *| [ -(year - start_year).abs, year ] }
            .to_h { |_, subject, number, value| [ [ subject, number ], value ] }
      end
    end
  end
end
