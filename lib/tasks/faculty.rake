# frozen_string_literal: true

namespace :faculty do
  desc "List all faculty members missing RMP IDs"
  task list_missing_rmp_ids: :environment do
    missing = Faculty.where(rmp_id: nil).order(:last_name, :first_name)

    if missing.empty?
      puts "✓ All faculty members have RMP IDs assigned!"
    else
      puts "\nFaculty missing RMP IDs (#{missing.count} total):\n"
      puts "-" * 80

      missing.each do |faculty|
        courses_count = faculty.courses.count
        puts "ID: #{faculty.id.to_s.rjust(5)} | #{faculty.full_name.ljust(30)} | Email: #{faculty.email.ljust(30)} | Courses: #{courses_count}"
      end

      puts "-" * 80
      puts "\nTotal: #{missing.count} faculty members without RMP IDs"
    end
  end

  desc "Fill in missing RMP IDs by searching Rate My Professor"
  task fill_missing_rmp_ids: :environment do
    missing = Faculty.where(rmp_id: nil).order(:last_name, :first_name)

    if missing.empty?
      puts "✓ All faculty members already have RMP IDs assigned!"
      next
    end

    puts "\nProcessing #{missing.count} faculty members without RMP IDs..."
    puts "-" * 80

    success_count = 0
    not_found_count = 0
    error_count = 0

    missing.each_with_index do |faculty, index|
      print "[#{(index + 1).to_s.rjust(3)}/#{missing.count}] #{faculty.full_name.ljust(30)} ... "

      begin
        # Use the existing job logic but run it synchronously
        UpdateFacultyRatingsJob.perform_now(faculty.id)

        # Reload to check if rmp_id was found
        faculty.reload

        if faculty.rmp_id.present?
          puts "✓ Found! (ID: #{faculty.rmp_id})"
          success_count += 1
        else
          puts "✗ Not found"
          not_found_count += 1
        end
      rescue => e
        puts "✗ Error: #{e.message}"
        error_count += 1
      end

      # Add a small delay to avoid rate limiting
      sleep 0.5
    end

    puts "-" * 80
    puts "\nResults:"
    puts "  ✓ Successfully linked: #{success_count}"
    puts "  ✗ Not found:          #{not_found_count}"
    puts "  ✗ Errors:             #{error_count}"
    puts "\nTotal processed:      #{missing.count}"
  end

  desc "Search for a specific faculty member on Rate My Professor by name"
  task :search, [:name] => :environment do |_t, args|
    if args[:name].blank?
      puts "Usage: rake faculty:search['John Doe']"
      next
    end

    service = RateMyProfessorService.new

    puts "\nSearching Rate My Professor for: #{args[:name]}"
    puts "-" * 80

    begin
      result = service.search_professors(args[:name], count: 10)
      teachers = result.dig("data", "newSearch", "teachers", "edges") || []

      if teachers.empty?
        puts "No results found."
      else
        puts "Found #{teachers.count} result(s):\n\n"

        teachers.each_with_index do |edge, index|
          teacher = edge["node"]
          school = teacher.dig("school", "name") || "Unknown School"
          department = teacher["department"] || "Unknown Dept"

          puts "#{index + 1}. #{teacher['firstName']} #{teacher['lastName']}"
          puts "   RMP ID:     #{teacher['id']}"
          puts "   School:     #{school}"
          puts "   Department: #{department}"
          puts "   Rating:     #{teacher['avgRating'] || 'N/A'} (#{teacher['numRatings'] || 0} ratings)"
          puts "   Difficulty: #{teacher['avgDifficulty'] || 'N/A'}"
          puts ""
        end
      end
    rescue => e
      puts "Error searching: #{e.message}"
    end
  end

  desc "Manually assign RMP ID to a faculty member"
  task :assign_rmp_id, [:faculty_id, :rmp_id] => :environment do |_t, args|
    if args[:faculty_id].blank? || args[:rmp_id].blank?
      puts "Usage: rake faculty:assign_rmp_id[faculty_id,rmp_id]"
      puts "Example: rake faculty:assign_rmp_id[123,'VGVhY2hlci0xMjM0NTY3']"
      next
    end

    begin
      faculty = Faculty.find(args[:faculty_id])

      puts "\nAssigning RMP ID to faculty:"
      puts "  Name:        #{faculty.full_name}"
      puts "  Current ID:  #{faculty.rmp_id || '(none)'}"
      puts "  New ID:      #{args[:rmp_id]}"

      faculty.update!(rmp_id: args[:rmp_id])

      puts "\n✓ RMP ID assigned successfully!"
      puts "\nFetching ratings for this faculty member..."

      # Fetch ratings immediately
      UpdateFacultyRatingsJob.perform_now(faculty.id)

      faculty.reload
      stats = faculty.rmp_stats

      if stats
        puts "\n✓ Ratings fetched successfully!"
        puts "  Avg Rating:     #{stats[:avg_rating]}"
        puts "  Avg Difficulty: #{stats[:avg_difficulty]}"
        puts "  Num Ratings:    #{stats[:num_ratings]}"
        puts "  Would Retake:   #{stats[:would_take_again_percent]}%"
      else
        puts "\n✗ Could not fetch ratings (check if RMP ID is correct)"
      end
    rescue ActiveRecord::RecordNotFound
      puts "✗ Faculty with ID #{args[:faculty_id]} not found"
    rescue ActiveRecord::RecordInvalid => e
      puts "✗ Error: #{e.message}"
    rescue => e
      puts "✗ Error: #{e.message}"
    end
  end

  desc "Update ratings for all faculty with RMP IDs"
  task update_all_ratings: :environment do
    faculty_with_ids = Faculty.where.not(rmp_id: nil)

    puts "\nUpdating ratings for #{faculty_with_ids.count} faculty members..."
    puts "-" * 80

    faculty_with_ids.find_each.with_index do |faculty, index|
      print "[#{(index + 1).to_s.rjust(3)}/#{faculty_with_ids.count}] #{faculty.full_name.ljust(30)} ... "

      begin
        UpdateFacultyRatingsJob.perform_now(faculty.id)
        puts "✓ Updated"
      rescue => e
        puts "✗ Error: #{e.message}"
      end

      # Small delay to avoid rate limiting
      sleep 0.5
    end

    puts "-" * 80
    puts "\n✓ Complete!"
  end
end
