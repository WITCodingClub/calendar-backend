# frozen_string_literal: true

namespace :prerequisites do
  desc "Scrape prerequisites from catalog.wit.edu for all subjects in the database"
  task scrape_catalog: :environment do
    require "net/http"
    require "nokogiri"

    subjects = Course.distinct.pluck(:subject).compact.sort
    puts "Found #{subjects.count} subjects to scrape: #{subjects.join(', ')}"

    total_created = 0
    total_updated = 0
    total_errors = 0

    subjects.each do |subject|
      dept = subject.downcase
      url = URI("https://catalog.wit.edu/course-descriptions/#{dept}/")
      puts "\nScraping #{url}..."

      begin
        response = Net::HTTP.get_response(url)

        unless response.is_a?(Net::HTTPSuccess)
          puts "  WARNING: HTTP #{response.code} for #{url}, skipping."
          next
        end

        doc = Nokogiri::HTML(response.body)
        course_blocks = doc.css(".courseblock")

        if course_blocks.empty?
          puts "  No course blocks found for #{subject}, skipping."
          next
        end

        puts "  Found #{course_blocks.count} course blocks."
        created = 0
        updated = 0
        errors = 0

        course_blocks.each do |block|
          title_el = block.at_css(".courseblocktitle")
          next unless title_el

          title_text = title_el.text.strip
          # Extract course number from title like "COMP 1000 Introduction to..."
          title_match = title_text.match(/\b#{Regexp.escape(subject)}\s+(\d{4})\b/i)
          next unless title_match

          course_number = title_match[1].to_i

          # Find matching Course records in the DB (may be multiple terms)
          courses = Course.where(subject: subject, course_number: course_number)
          next if courses.empty?

          # Parse prerequisite blocks
          prereq_nodes = block.css(".courseblockreq")
          prereq_nodes.each do |req_node|
            label_el = req_node.at_css("strong")
            next unless label_el

            label = label_el.text.strip.downcase

            prereq_type = if label.include?("corequisite")
                            "corequisite"
                          elsif label.include?("prerequisite")
                            "prerequisite"
                          elsif label.include?("recommended")
                            "recommended"
                          else
                            next
                          end

            # Get the rule text by removing the label portion
            rule_text = req_node.text.strip
            label_text = label_el.text.strip
            rule_text = rule_text.sub(/\A#{Regexp.escape(label_text)}\s*/i, "").strip
            next if rule_text.blank?

            courses.each do |course|
              existing = CoursePrerequisite.find_by(
                course_id: course.id,
                prerequisite_type: prereq_type,
                prerequisite_rule: rule_text
              )

              if existing
                updated += 1
              else
                begin
                  CoursePrerequisite.create!(
                    course: course,
                    prerequisite_type: prereq_type,
                    prerequisite_rule: rule_text
                  )
                  created += 1
                rescue ActiveRecord::RecordInvalid => e
                  puts "    ERROR creating prerequisite for #{subject} #{course_number}: #{e.message}"
                  errors += 1
                end
              end
            end
          end
        rescue => e
          puts "  ERROR processing block: #{e.message}"
          errors += 1
        end

        puts "  #{subject}: #{created} created, #{updated} already existed, #{errors} errors."
        total_created += created
        total_updated += updated
        total_errors += errors

      rescue => e
        puts "  ERROR scraping #{subject}: #{e.message}"
        total_errors += 1
      end
    end

    puts "\n#{'=' * 60}"
    puts "Scrape complete!"
    puts "Total created:       #{total_created}"
    puts "Total already exist: #{total_updated}"
    puts "Total errors:        #{total_errors}"
  end
end
