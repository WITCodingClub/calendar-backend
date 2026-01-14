# frozen_string_literal: true

namespace :embeddings do
  desc "Generate embeddings for all records missing them"
  task backfill: :environment do
    puts "Starting embedding backfill..."

    models = [Course, Faculty, RmpRating]

    models.each do |model|
      count = model.without_embeddings.count
      puts "\n#{model.name}: #{count} records without embeddings"

      next if count.zero?

      model.without_embeddings.find_each do |record|
        GenerateEmbeddingJob.perform_later(model.name, record.id)
      end

      puts "  Queued #{count} jobs for #{model.name}"
    end

    puts "\nBackfill jobs queued! Run `bin/rails solid_queue:start` to process them."
  end

  desc "Generate embeddings synchronously (useful for small datasets or testing)"
  task backfill_sync: :environment do
    puts "Starting synchronous embedding backfill..."

    service = EmbeddingService.new
    models = [Course, Faculty, RmpRating]

    models.each do |model|
      records = model.without_embeddings
      count = records.count
      puts "\n#{model.name}: #{count} records without embeddings"

      next if count.zero?

      success = 0
      records.find_each.with_index do |record, index|
        if service.embed_record(record)
          success += 1
        end

        # Progress indicator
        print "." if (index + 1) % 10 == 0
        print " #{index + 1}/#{count}" if (index + 1) % 100 == 0
      end

      puts "\n  Generated #{success}/#{count} embeddings for #{model.name}"
    end

    puts "\nBackfill complete!"
  end

  desc "Generate embeddings for a specific model"
  task :backfill_model, [:model_name] => :environment do |_t, args|
    model_name = args[:model_name]

    if model_name.blank?
      puts "Usage: rails embeddings:backfill_model[ModelName]"
      puts "Available models: Course, Faculty, RmpRating"
      exit 1
    end

    begin
      model = model_name.constantize
    rescue NameError
      puts "Unknown model: #{model_name}"
      exit 1
    end

    unless model.column_names.include?("embedding")
      puts "Model #{model_name} does not have an embedding column"
      exit 1
    end

    count = model.without_embeddings.count
    puts "#{model_name}: #{count} records without embeddings"

    if count.zero?
      puts "Nothing to do!"
      exit 0
    end

    model.without_embeddings.find_each do |record|
      GenerateEmbeddingJob.perform_later(model_name, record.id)
    end

    puts "Queued #{count} jobs for #{model_name}"
    puts "Run `bin/rails solid_queue:start` to process them."
  end

  desc "Show embedding statistics"
  task stats: :environment do
    puts "Embedding Statistics"
    puts "=" * 40

    models = [Course, Faculty, RmpRating]

    models.each do |model|
      total = model.count
      with_embeddings = model.with_embeddings.count
      without_embeddings = model.without_embeddings.count
      percentage = total.positive? ? (with_embeddings.to_f / total * 100).round(1) : 0

      puts "\n#{model.name}:"
      puts "  Total:             #{total}"
      puts "  With embeddings:   #{with_embeddings} (#{percentage}%)"
      puts "  Without embeddings: #{without_embeddings}"
    end
  end

  desc "Clear all embeddings (use with caution!)"
  task clear: :environment do
    puts "WARNING: This will clear all embeddings from the database!"
    print "Type 'yes' to continue: "

    confirmation = $stdin.gets.chomp
    unless confirmation == "yes"
      puts "Aborted."
      exit 1
    end

    models = [Course, Faculty, RmpRating]

    models.each do |model|
      count = model.with_embeddings.count
      # rubocop:disable Rails/SkipsModelValidations -- Bulk clear for efficiency
      model.with_embeddings.update_all(embedding: nil)
      # rubocop:enable Rails/SkipsModelValidations
      puts "Cleared #{count} embeddings from #{model.name}"
    end

    puts "Done!"
  end
end
