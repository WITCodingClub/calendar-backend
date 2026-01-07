# frozen_string_literal: true

namespace :calendars do
  desc "Delete all user Google calendars to clean up orphaned events"
  task delete_all: :environment do
    puts "🗑️  Starting calendar deletion process..."
    
    # Find all Google calendars
    calendars = GoogleCalendar.includes(:oauth_credential)
    total_calendars = calendars.count
    
    puts "Found #{total_calendars} calendars to delete"
    
    if total_calendars == 0
      puts "No calendars found to delete"
      exit
    end
    
    # Confirm deletion in production
    if Rails.env.production?
      print "⚠️  You are about to delete #{total_calendars} calendars in PRODUCTION. Type 'DELETE' to confirm: "
      confirmation = STDIN.gets.chomp
      unless confirmation == 'DELETE'
        puts "❌ Deletion cancelled"
        exit
      end
    end
    
    deleted_count = 0
    error_count = 0
    
    calendars.find_each do |calendar|
      begin
        user_email = calendar.oauth_credential&.user&.email || "unknown"
        puts "Deleting calendar for user: #{user_email} (Calendar ID: #{calendar.google_calendar_id})"
        
        # Delete from Google Calendar API
        GoogleCalendarService.new(calendar.oauth_credential.user).delete_calendar(calendar.google_calendar_id)
        
        # Delete local records
        calendar.google_calendar_events.destroy_all
        calendar.destroy!
        
        deleted_count += 1
        puts "✅ Successfully deleted calendar for #{user_email}"
        
      rescue => e
        error_count += 1
        puts "❌ Failed to delete calendar for #{user_email}: #{e.message}"
        
        # Still delete local records even if Google API call fails
        begin
          calendar.google_calendar_events.destroy_all
          calendar.destroy!
          puts "🧹 Cleaned up local records for #{user_email}"
        rescue => local_error
          puts "❌ Failed to clean up local records: #{local_error.message}"
        end
      end
      
      # Small delay to avoid hitting rate limits
      sleep(0.1)
    end
    
    puts "\n📊 Summary:"
    puts "Total calendars processed: #{total_calendars}"
    puts "Successfully deleted: #{deleted_count}"
    puts "Errors encountered: #{error_count}"
    puts "🏁 Calendar deletion complete!"
  end
  
  desc "Recreate Google calendars for all users with OAuth credentials"
  task recreate_all: :environment do
    puts "🏗️  Starting calendar recreation process..."
    
    # Find all OAuth credentials with valid access tokens
    oauth_credentials = OauthCredential.where(provider: 'google')
                                      .joins(:user)
                                      .where.not(access_token: [nil, ''])
    
    total_credentials = oauth_credentials.count
    puts "Found #{total_credentials} OAuth credentials to process"
    
    if total_credentials == 0
      puts "No OAuth credentials found"
      exit
    end
    
    created_count = 0
    error_count = 0
    skipped_count = 0
    
    oauth_credentials.find_each do |credential|
      begin
        user = credential.user
        user_email = user.email || "unknown"
        
        # Skip if calendar already exists
        if credential.google_calendar.present?
          puts "📅 Calendar already exists for #{user_email}, skipping"
          skipped_count += 1
          next
        end
        
        puts "Creating calendar for user: #{user_email}"
        
        # Create new calendar
        service = GoogleCalendarService.new(user)
        calendar_response = service.create_or_get_course_calendar
        
        if calendar_response[:success]
          puts "✅ Successfully created calendar for #{user_email}"
          created_count += 1
        else
          puts "❌ Failed to create calendar for #{user_email}: #{calendar_response[:error]}"
          error_count += 1
        end
        
      rescue => e
        error_count += 1
        puts "❌ Error processing #{user_email}: #{e.message}"
      end
      
      # Small delay to avoid hitting rate limits
      sleep(0.1)
    end
    
    puts "\n📊 Summary:"
    puts "Total credentials processed: #{total_credentials}"
    puts "Successfully created: #{created_count}"
    puts "Skipped (already exists): #{skipped_count}"
    puts "Errors encountered: #{error_count}"
    puts "🏁 Calendar recreation complete!"
  end
  
  desc "Delete and recreate all user Google calendars (combines delete_all and recreate_all)"
  task rebuild_all: :environment do
    puts "🔄 Starting complete calendar rebuild process..."
    
    # First delete all calendars
    Rake::Task['calendars:delete_all'].invoke
    
    puts "\n⏸️  Waiting 5 seconds before recreation..."
    sleep(5)
    
    # Then recreate them
    Rake::Task['calendars:recreate_all'].invoke
    
    puts "\n🎉 Complete calendar rebuild finished!"
  end
end