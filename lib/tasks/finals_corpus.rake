# frozen_string_literal: true

namespace :finals do
  desc "Parse every PDF in DIR with FinalsSchedules::TableParser and print counts and warnings. " \
       "Use it to check a new PDF format before an upload."
  task check_corpus: :environment do
    dir = ENV.fetch("DIR") { abort "Pass DIR=<folder of finals PDFs>" }

    Dir[File.join(dir, "*.pdf")].sort.each do |path|
      parser  = FinalsSchedules::TableParser.new
      entries = parser.parse(PdfText.extract(File.binread(path)))

      puts "#{File.basename(path)}: #{entries.size} CRNs, " \
           "#{entries.count { |e| e[:combined_crns].size > 1 }} combined, " \
           "#{entries.count { |e| e[:location].nil? }} with no room, #{parser.warnings.size} warnings"
      parser.warnings.each { |warning| puts "  ! #{warning}" }
    end
  end
end
