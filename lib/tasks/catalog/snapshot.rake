# frozen_string_literal: true

namespace :catalog do
  namespace :snapshot do
    desc "Export the public catalog to a gzipped JSON file (FILE=tmp/catalog.json.gz TERMS=3)"
    task export: :environment do
      path = ENV.fetch("FILE", "tmp/catalog.json.gz")
      term_count = Integer(ENV.fetch("TERMS", Catalog::Snapshot::DEFAULT_TERM_COUNT))

      data = Catalog::Snapshot.export(term_count: term_count)
      Catalog::Snapshot.write(path, data)

      counts = data["tables"].filter_map { |table, rows| "#{rows.size} #{table}" if rows.any? }
      puts "Wrote #{path}: #{counts.join(", ")}"
    end

    desc "Import a catalog snapshot into empty catalog tables (FILE=db/seeds/catalog.json.gz)"
    task import: :environment do
      path = ENV.fetch("FILE", Catalog::Snapshot::SEED_PATH.to_s)

      Catalog::Snapshot.import(Catalog::Snapshot.read(path))
      puts "Imported #{path}"
    end
  end
end
