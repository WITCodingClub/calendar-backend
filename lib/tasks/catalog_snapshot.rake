# frozen_string_literal: true

namespace :catalog_snapshot do
  desc "Export the public catalog to a gzipped JSON file (FILE=tmp/catalog.json.gz TERMS=3)"
  task export: :environment do
    path = ENV.fetch("FILE", "tmp/catalog.json.gz")
    term_count = Integer(ENV.fetch("TERMS", CatalogSnapshot::DEFAULT_TERM_COUNT))

    data = CatalogSnapshot.export(term_count: term_count)
    CatalogSnapshot.write(path, data)

    counts = data["tables"].filter_map { |table, rows| "#{rows.size} #{table}" if rows.any? }
    puts "Wrote #{path}: #{counts.join(", ")}"
  end

  desc "Import a catalog snapshot into empty catalog tables (FILE=db/seeds/catalog.json.gz)"
  task import: :environment do
    path = ENV.fetch("FILE", CatalogSnapshot::SEED_PATH.to_s)

    CatalogSnapshot.import(CatalogSnapshot.read(path))
    puts "Imported #{path}"
  end
end
