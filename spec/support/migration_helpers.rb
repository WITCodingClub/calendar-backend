# frozen_string_literal: true

# A migration built with `Migration.new` has no version, so strong_migrations
# checks it as a new migration. build_migration reads the version from the
# name of the file that defines the class, as `db:migrate` does. Migrations
# from before StrongMigrations.start_after then skip the checks, and new ones
# get them.
module MigrationHelpers
  def build_migration(klass = described_class)
    file, = Object.const_source_location(klass.name)
    version = File.basename(file.to_s)[/\A\d+/]
    raise ArgumentError, "#{klass} is not defined in a migration file: #{file.inspect}" unless version

    klass.new(klass.name, version.to_i)
  end
end

RSpec.configure do |config|
  config.include MigrationHelpers, file_path: %r{spec/migrations/}
end
