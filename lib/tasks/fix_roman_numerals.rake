namespace :courses do
  desc "Fix Roman numerals in course titles (e.g., 'Computer Science Ii' -> 'Computer Science II')"
  task fix_roman_numerals: :environment do
    include ApplicationHelper

    puts "Finding courses with incorrect Roman numerals..."
    
    # Find courses that have lowercase Roman numerals that should be uppercase
    # Common patterns: "Ii", "Iii", "Iv", "Vi", "Vii", "Viii", "Ix"
    incorrect_patterns = [
      /\bIi\b/,     # "Computer Science Ii"
      /\bIii\b/,    # "Computer Science Iii"  
      /\bIv\b/,     # "Computer Science Iv"
      /\bVi\b/,     # "Computer Science Vi"
      /\bVii\b/,    # "Computer Science Vii"
      /\bViii\b/,   # "Computer Science Viii"
      /\bIx\b/      # "Computer Science Ix"
    ]
    
    courses_to_fix = Course.where(
      incorrect_patterns.map { |pattern| "title ~ ?" }.join(" OR "),
      *incorrect_patterns.map(&:source)
    )
    
    puts "Found #{courses_to_fix.count} courses with incorrect Roman numerals"
    
    if courses_to_fix.count == 0
      puts "No courses need fixing!"
      next
    end
    
    puts "\nCourses that will be updated:"
    courses_to_fix.find_each do |course|
      old_title = course.title
      new_title = titleize_with_roman_numerals(old_title)
      puts "CRN #{course.crn}: '#{old_title}' -> '#{new_title}'"
    end
    
    print "\nProceed with updating #{courses_to_fix.count} courses? (y/N): "
    response = STDIN.gets.chomp.downcase
    
    unless response == 'y' || response == 'yes'
      puts "Cancelled."
      next
    end
    
    puts "\nUpdating courses..."
    updated_count = 0
    failed_count = 0
    
    courses_to_fix.find_each do |course|
      begin
        old_title = course.title
        new_title = titleize_with_roman_numerals(old_title)
        
        # Only update if the title actually changes
        if old_title != new_title
          course.update!(title: new_title)
          updated_count += 1
          puts "✓ CRN #{course.crn}: Updated to '#{new_title}'"
        end
      rescue => e
        failed_count += 1
        puts "✗ CRN #{course.crn}: Failed - #{e.message}"
      end
    end
    
    puts "\n" + "="*50
    puts "SUMMARY:"
    puts "Total courses processed: #{courses_to_fix.count}"
    puts "Successfully updated: #{updated_count}"
    puts "Failed: #{failed_count}"
    puts "="*50
  end
end