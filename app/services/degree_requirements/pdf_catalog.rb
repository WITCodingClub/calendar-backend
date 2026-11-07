# frozen_string_literal: true

module DegreeRequirements
  # The catalog years that exist only as PDFs (2013-2014 to 2018-2019), and
  # the 2025-2026 PDF for the programs that the Wayback Machine does not
  # have (#865). docs/degree-requirements.md describes each layout.
  module PdfCatalog
    # The file name under /previous-catalogs/ for each start year.
    FILES = {
      2013 => "WIT_2013-14_Academic_Catalog_.pdf",
      2014 => "WIT_2014-15_Academic_Catalog_.pdf",
      2015 => "WIT_2015-2016_Academic_Catalog.pdf",
      2016 => "WIT_2016-2017_Academic_Catalog.pdf",
      2017 => "WIT_2017-18_Academic_Catalog.pdf",
      2018 => "2018-2019_Academic_Catalog_Final_update_5_101519.pdf",
      2025 => "2025-2026_Academic_Catalog.pdf"
    }.freeze

    # 2013-2014 to 2015-2016 are Word tables with a column for each
    # semester. 2016-2017 to 2018-2019 list each semester under a heading.
    # 2025-2026 is a CourseLeaf PDF with two columns on a page.
    LAYOUTS = { 2013 => :grid, 2014 => :grid, 2015 => :grid,
                2016 => :list, 2017 => :list, 2018 => :list,
                2025 => :courseleaf }.freeze

    # The first year with an HTML catalog. Older years come only from a PDF.
    FIRST_HTML_YEAR = 2019

    # One plan of study as a PDF prints it. `title` is the heading over it,
    # such as "COMPUTER NETWORKING (BSCN)", and `code` the program code in
    # it. `page` is the 1-based PDF page the plan starts on.
    Program = Data.define(:title, :code, :page, :plan)

    module_function

    def url_for(start_year)
      file = FILES[start_year]
      file && "#{SITE_URL}/previous-catalogs/#{file}"
    end

    def parser_for(start_year)
      case LAYOUTS[start_year]
      when :grid then GridParser
      when :list then ListParser
      when :courseleaf then CourseLeafParser
      end
    end

    def pdf_only?(start_year) = start_year < FIRST_HTML_YEAR && FILES.key?(start_year)
  end
end
