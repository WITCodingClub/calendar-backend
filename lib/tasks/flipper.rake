# frozen_string_literal: true

require_relative '../../app/lib/flipper_flags' unless defined?(FlipperFlags)

namespace :flipper do
  desc "Ensure all declared feature flags exist in Flipper"
  task ensure_flags: :environment do
    created_count = 0
    
    FlipperFlags::MAP.each_value do |flag|
      unless Flipper.exist?(flag)
        Flipper.add(flag)
        puts "Created feature flag: #{flag}"
        created_count += 1
      end
    end
    
    if created_count.zero?
      puts "All feature flags already exist (#{FlipperFlags::MAP.size} total)"
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
end