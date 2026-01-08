# frozen_string_literal: true

namespace :flipper do
  desc "Ensure all declared feature flags exist in Flipper"
  task ensure_flags: :environment do
    created_count = 0
    
    # FlipperFlags should be auto-loaded by Rails
    FlipperFlags::MAP.each do |name, flag|
      unless Flipper.exist?(flag)
        Flipper.add(flag)
        puts "Created feature flag: #{name} (#{flag})"
        created_count += 1
      else
        puts "Flag already exists: #{name} (#{flag})"
      end
    end
    
    if created_count.zero?
      puts "All #{FlipperFlags::MAP.size} feature flags already exist"
    else
      puts "Created #{created_count} new feature flags"
    end
  end
  
  desc "List all declared feature flags and their status"
  task list_flags: :environment do
    puts "Declared Feature Flags:"
    puts "=" * 50
    
    FlipperFlags::MAP.each do |name, flag|
      exists = Flipper.exist?(flag)
      status = exists ? "✓ EXISTS" : "✗ MISSING"
      puts "#{name.to_s.ljust(20)} #{flag.to_s.ljust(25)} #{status}"
    end
  end
  
  desc "Remove test feature flags"
  task clean_test_flags: :environment do
    test_flags = Flipper.features.select { |f| f.key.start_with?('test_') }
    test_flags.each do |flag|
      Flipper.remove(flag.key)
      puts "Removed test flag: #{flag.key}"
    end
    puts "Cleaned #{test_flags.size} test flags"
  end
end