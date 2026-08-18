# frozen_string_literal: true

# One-time repairs for course rows that were imported before a fix landed.
# Both tasks are safe to run again: they only write a column when the value
# from Banner is different from the value in the database.
namespace :backfill do
  # Banner is a shared system. Keep the request rate low.
  def backfill_pause
    0.2
  end

  def backfill_terms(term_uid)
    if term_uid.present?
      term = Term.find_by(uid: term_uid)
      raise "Term with UID #{term_uid} not found." unless term

      [ term ]
    else
      # Terms that hold courses and are not over. Banner does not answer for
      # terms that have closed, and their seat counts are of no use anyway.
      Term.current_and_future
          .where(id: Course.select(:term_id).distinct)
          .to_a
    end
  end

  desc "Fill in seats_capacity and seats_available for courses that have none (term_uid optional)"
  task :seats, [ :term_uid ] => :environment do |_, args|
    terms = backfill_terms(args[:term_uid])
    raise "No terms to process." if terms.empty?

    puts "Backfilling seat counts for: #{terms.map(&:name).join(', ')}"

    terms.each do |term|
      scope = Course.where(term: term)
                    .where(seats_capacity: nil)
                    .or(Course.where(term: term).where(seats_available: nil))

      total = scope.count
      puts "\n#{term.name} (#{term.uid}): #{total} courses without seat counts."
      next if total.zero?

      updated = 0
      missing = 0
      failed  = 0

      scope.find_each(batch_size: 50).with_index do |course, index|
        begin
          info = LeopardWebService.get_enrollment_info(
            term: term.uid.to_s,
            course_reference_number: course.crn.to_s
          )

          capacity  = info&.dig(:enrollment, :maximum)
          available = info&.dig(:enrollment, :seats_available)

          if capacity.nil? && available.nil?
            missing += 1
          else
            attrs = {}
            attrs[:seats_capacity]  = capacity  unless capacity.nil?
            attrs[:seats_available] = available unless available.nil?
            course.update_columns(attrs) if attrs.any?
            updated += 1
          end
        rescue => e
          failed += 1
          puts "  CRN #{course.crn}: #{e.message}"
        end

        print "  #{index + 1}/#{total}\r"
        sleep backfill_pause
      end

      puts "  Updated #{updated}. No data for #{missing}. Failed #{failed}."
    end

    puts "\nSeat backfill done."
  end

  desc "Fill in link_identifier and is_section_linked from the Banner catalog (term_uid optional)"
  task :link_identifiers, [ :term_uid ] => :environment do |_, args|
    terms = backfill_terms(args[:term_uid])
    raise "No terms to process." if terms.empty?

    puts "Backfilling link identifiers for: #{terms.map(&:name).join(', ')}"

    terms.each do |term|
      puts "\n#{term.name} (#{term.uid}): fetching the catalog..."
      result = LeopardWebService.get_course_catalog(term: term.uid.to_s)

      unless result[:success]
        puts "  Catalog fetch failed: #{result[:error]}"
        next
      end

      rows = result[:courses] || []
      puts "  Banner returned #{rows.length} sections."

      # Only the two link columns are written here. A full re-import would also
      # rewrite meeting times and faculty, which this repair does not need.
      by_crn = Course.where(term: term).pluck(:crn, :id, :link_identifier, :is_section_linked)
                     .index_by { |row| row[0].to_s }

      updated = 0
      skipped = 0
      unknown = 0

      rows.each do |row|
        crn = row["courseReferenceNumber"].to_s
        record = by_crn[crn]

        if record.nil?
          unknown += 1
          next
        end

        _, id, current_identifier, current_linked = record
        identifier = row["linkIdentifier"].presence
        linked     = ActiveModel::Type::Boolean.new.cast(row["isSectionLinked"]) || false

        if current_identifier == identifier && current_linked == linked
          skipped += 1
          next
        end

        Course.where(id: id).update_all(
          link_identifier:   identifier,
          is_section_linked: linked
        )
        updated += 1
      end

      puts "  Updated #{updated}. Already correct #{skipped}. Not in the database #{unknown}."
    end

    puts "\nLink identifier backfill done."
  end
end
