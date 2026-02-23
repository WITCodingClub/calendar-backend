# frozen_string_literal: true

namespace :transfer do
  desc "Sync transfer equivalency database from TES"
  task sync_equivalencies: :environment do
    puts "Syncing transfer equivalencies from TES..."
    result = Transfer::EquivalencySyncService.call

    puts "Results:"
    puts "  Universities synced: #{result[:universities_synced]}"
    puts "  Courses synced: #{result[:courses_synced]}"
    puts "  Equivalencies synced: #{result[:equivalencies_synced]}"

    if result[:errors].any?
      puts "  Errors (#{result[:errors].size}):"
      result[:errors].each { |e| puts "    - #{e}" }
    end
  end
end
