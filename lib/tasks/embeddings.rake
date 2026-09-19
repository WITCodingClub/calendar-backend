# frozen_string_literal: true

namespace :embeddings do
  desc "Queue embeddings for every record whose text changed. Pass a model to do one: embeddings:backfill[Course]"
  task :backfill, [ :model ] => :environment do |_, args|
    unless EmbeddingService.configured?
      abort "OPENAI_API_KEY is not set. See docs/embeddings.md."
    end

    model = args[:model].presence
    if model && !BackfillEmbeddingsJob::SCOPES.key?(model)
      abort "Unknown model #{model.inspect}. Use one of: #{BackfillEmbeddingsJob::SCOPES.keys.join(', ')}"
    end

    puts "Queueing #{model || 'all models'}..."
    BackfillEmbeddingsJob.perform_now(model)
    puts "Done. GenerateEmbeddingsJob runs the batches on the low queue."
  end

  desc "Embed the records of one model right now, without the queue: embeddings:run[Course]"
  task :run, [ :model ] => :environment do |_, args|
    model = args[:model].presence
    abort "Usage: rake embeddings:run[Course]" if model.blank?
    abort "OPENAI_API_KEY is not set. See docs/embeddings.md." unless EmbeddingService.configured?

    scope = BackfillEmbeddingsJob::SCOPES.fetch(model) { abort "Unknown model #{model.inspect}" }.call
    done  = 0

    scope.find_in_batches(batch_size: BackfillEmbeddingsJob::BATCH_SIZE) do |records|
      ids = records.select(&:embedding_stale?).map(&:id)
      next if ids.empty?

      GenerateEmbeddingsJob.perform_now(model, ids)
      done += ids.length
      print "Embedded #{done}...\r"
    end

    puts "\nEmbedded #{done} #{model} record(s)."
  end

  desc "Show how much of each model is embedded"
  task status: :environment do
    puts "OPENAI_API_KEY: #{EmbeddingService.configured? ? 'set' : 'missing'}"
    puts "Model: #{EmbeddingService::MODEL} (#{EmbeddingService::DIMENSIONS} dimensions)"
    puts

    BackfillEmbeddingsJob::SCOPES.each do |model, scope|
      relation = scope.call
      total    = relation.count
      embedded = relation.embedded.count
      stale    = relation.find_each.count(&:embedding_stale?)

      puts format("%-10s %6d records, %6d embedded, %6d stale", model, total, embedded, stale)
    end
  end
end
