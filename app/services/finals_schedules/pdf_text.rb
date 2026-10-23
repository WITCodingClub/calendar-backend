# frozen_string_literal: true

require "open3"
require "tempfile"

module FinalsSchedules
  # Extracts the text of a finals PDF with `pdftotext -layout`, which keeps
  # each table row on one line.
  module PdfText
    module_function

    def extract(pdf_content)
      Tempfile.create([ "finals_schedule", ".pdf" ], binmode: true) do |tmp|
        tmp.write(pdf_content)
        tmp.flush

        begin
          stdout, stderr, status = Open3.capture3("pdftotext", "-layout", tmp.path, "-")
        rescue Errno::ENOENT
          raise "pdftotext is not installed. Install poppler-utils (brew install poppler on Mac)"
        end

        unless status.success?
          raise "Failed to extract text from PDF: #{stderr.presence || 'Unknown error'}. " \
                "Make sure pdftotext is installed (brew install poppler on Mac)"
        end

        stdout
      end
    end
  end
end
