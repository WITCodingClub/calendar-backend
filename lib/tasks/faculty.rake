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
        puts "ID: #{faculty.id.to_s.rjust(5)} | #{faculty.full_name.ljust(30)} | Email: #{faculty.email.ljust(30)} | Courses: #{faculty.courses.count}"
      end

      puts "-" * 80
      puts "\nTotal: #{missing.count} faculty members without RMP IDs"
    end
  end

  desc "Search for a specific faculty member on Rate My Professor by name"
  task :search, [ :name ] => :environment do |_t, args|
    if args[:name].blank?
      puts "Usage: rake faculty:search['John Doe']"
      next
    end

    service = Faculties::RateMyProfessorClient.new
    puts "\nSearching Rate My Professor for: #{args[:name]}"
    puts "-" * 80

    begin
      result   = service.search_professors(args[:name], count: 10)
      teachers = result.dig("data", "newSearch", "teachers", "edges") || []

      if teachers.empty?
        puts "No results found."
        name_parts = args[:name].split
        if name_parts.length >= 2
          rmp_url = service.add_professor_url(first_name: name_parts[0], last_name: name_parts[-1])
          puts "Manually add this professor:\n  #{rmp_url}"
        end
      else
        puts "Found #{teachers.count} result(s):\n\n"
        teachers.each_with_index do |edge, index|
          t = edge["node"]
          puts "#{index + 1}. #{t['firstName']} #{t['lastName']}"
          puts "   RMP ID:     #{t['id']}"
          puts "   School:     #{t.dig('school', 'name') || 'Unknown'}"
          puts "   Department: #{t['department'] || 'Unknown'}"
          puts "   Rating:     #{t['avgRating'] || 'N/A'} (#{t['numRatings'] || 0} ratings)"
          puts "   Difficulty: #{t['avgDifficulty'] || 'N/A'}"
          puts ""
        end
      end
    rescue => e
      puts "Error searching: #{e.message}"
    end
  end

  desc "Manually assign RMP ID to a faculty member"
  task :assign_rmp_id, [ :faculty_id, :rmp_id ] => :environment do |_t, args|
    if args[:faculty_id].blank? || args[:rmp_id].blank?
      puts "Usage: rake faculty:assign_rmp_id[faculty_id,rmp_id]"
      next
    end

    begin
      faculty = Faculty.find(args[:faculty_id])
      puts "\nAssigning RMP ID to faculty:"
      puts "  Name:       #{faculty.full_name}"
      puts "  Current ID: #{faculty.rmp_id || '(none)'}"
      puts "  New ID:     #{args[:rmp_id]}"

      faculty.update!(rmp_id: args[:rmp_id])
      puts "\n✓ RMP ID assigned successfully!"

      puts "\nFetching ratings..."
      Faculties::UpdateRatingsJob.perform_now(faculty.id)
      faculty.reload

      stats = faculty.rmp_stats
      if stats
        puts "✓ Ratings fetched!"
        puts "  Avg Rating:     #{stats[:avg_rating]}"
        puts "  Avg Difficulty: #{stats[:avg_difficulty]}"
        puts "  Num Ratings:    #{stats[:num_ratings]}"
        puts "  Would Retake:   #{stats[:would_take_again_percent]}%"
      else
        puts "✗ Could not fetch ratings (check if RMP ID is correct)"
      end
    rescue ActiveRecord::RecordNotFound
      puts "✗ Faculty with ID #{args[:faculty_id]} not found"
    rescue => e
      puts "✗ Error: #{e.message}"
    end
  end
end
