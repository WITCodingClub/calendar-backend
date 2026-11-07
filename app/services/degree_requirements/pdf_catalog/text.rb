# frozen_string_literal: true

require "open3"
require "tempfile"

module DegreeRequirements
  module PdfCatalog
    # The text of a catalog PDF from `pdftotext -layout`. Pages are split by
    # a form feed ("\f"). A CourseLeaf PDF has two columns on a letter page,
    # so each half is extracted on its own, and the left half of a page
    # comes before its right half.
    module Text
      PAGE_WIDTH = 612
      PAGE_HEIGHT = 792

      module_function

      def extract(pdf, columns: 1)
        Tempfile.create([ "catalog", ".pdf" ], binmode: true) do |file|
          file.write(pdf)
          file.flush
          text = columns == 2 ? halves(file.path) : pdftotext(file.path)
          # Postgres refuses a NUL byte, and a stray byte breaks every regex.
          # NFKC turns the "ﬁ" ligature of the CourseLeaf PDF into "fi".
          text.scrub.delete("\0").unicode_normalize(:nfkc)
        end
      end

      def halves(path)
        half = (PAGE_WIDTH / 2).to_s
        left = pdftotext(path, "-x", "0", "-y", "0", "-W", half, "-H", PAGE_HEIGHT.to_s)
        right = pdftotext(path, "-x", half, "-y", "0", "-W", half, "-H", PAGE_HEIGHT.to_s)
        interleave(left, right)
      end

      def interleave(left, right)
        left_pages = left.split("\f")
        right_pages = right.split("\f")
        Array.new([ left_pages.size, right_pages.size ].max) do |i|
          "#{left_pages[i]}\n#{right_pages[i]}"
        end.join("\f")
      end

      def pdftotext(path, *crop)
        stdout, stderr, status = Open3.capture3("pdftotext", "-layout", *crop, path, "-")
        raise Error, "pdftotext failed: #{stderr.presence || 'unknown error'}" unless status.success?

        stdout.dup.force_encoding(Encoding::UTF_8)
      rescue Errno::ENOENT
        raise Error, "pdftotext is not installed. Install poppler-utils (brew install poppler on Mac)"
      end
    end
  end
end
