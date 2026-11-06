# frozen_string_literal: true

module DegreeRequirements
  # The catalog years that are only PDFs (#865), and what the PDF parsers
  # give back. docs/degree-requirements.md describes the formats.
  #
  # The parsers read `pdftotext -layout` text. They keep a plan only when it
  # passes every check, and give the reason for each plan they leave out. A
  # wrong plan is worse than a missing one.
  module PdfCatalog
    BASE_URL = "#{SITE_URL}/previous-catalogs/".freeze

    # The file name on the previous catalogs page, and the parser for its
    # layout. 2013-2014 to 2015-2016 print each plan as a grid with a column
    # for each semester. 2016-2017 to 2018-2019 print a list under a heading
    # for each semester.
    FILES = {
      2013 => [ "WIT_2013-14_Academic_Catalog_.pdf", :grid ],
      2014 => [ "WIT_2014-15_Academic_Catalog_.pdf", :grid ],
      2015 => [ "WIT_2015-2016_Academic_Catalog.pdf", :grid ],
      2016 => [ "WIT_2016-2017_Academic_Catalog.pdf", :list ],
      2017 => [ "WIT_2017-18_Academic_Catalog.pdf", :list ],
      2018 => [ "2018-2019_Academic_Catalog_Final_update_5_101519.pdf", :list ]
    }.freeze

    # One plan of study. heading is the program name as printed above the
    # plan, such as "COMPUTER SCIENCE (BCOS)". line is where the plan starts
    # in the text, for the logs. warnings are checks that failed but did not
    # stop the parse, such as a printed total that does not match its rows.
    Plan = Data.define(:heading, :line, :items, :warnings) do
      def years = items.map(&:year_index).max
      def total_credits = items.all?(&:min_credits) ? items.sum(&:min_credits) : nil
    end

    # One row of a plan. title is the course title as printed, which the
    # course code aliases compare. label is the text of a placeholder.
    Item = Data.define(:year_index, :season, :kind, :subject_code, :course_number, :title, :label,
                       :min_credits, :max_credits, :options)

    # A plan that a parser left out, and why.
    Rejection = Data.define(:heading, :line, :reason)

    Result = Data.define(:plans, :rejections)

    YEAR_WORDS = {
      "freshman" => 1, "first" => 1, "sophomore" => 2, "second" => 2, "junior" => 3, "third" => 3,
      "senior" => 4, "fourth" => 4, "fifth" => 5
    }.freeze
    SEASONS = %w[fall spring summer].freeze

    # A page footer, such as "2014-2015 Academic Catalog   136   Rev 12 Feb 2015".
    FOOTER = /\A\s*(?:\d{4}-\d{4} Academic Catalog\b.*|\d{1,3})\s*\z/

    module_function

    def url_for(start_year)
      file = FILES.dig(start_year, 0)
      file && "#{BASE_URL}#{ERB::Util.url_encode(file)}"
    end

    def parser_for(start_year)
      case FILES.dig(start_year, 1)
      when :grid then PdfGridParser
      when :list then PdfListParser
      end
    end
  end
end
