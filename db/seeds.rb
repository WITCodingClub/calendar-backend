# frozen_string_literal: true

# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Example:
#
#   ["Action", "Comedy", "Drama", "Horror"].each do |genre_name|
#     MovieGenre.find_or_create_by!(name: genre_name)
#   end

# Load degree programs and transfer universities seed data
# Only run in development/test environments to avoid polluting production
if Rails.env.local?
  Rails.logger.debug "Loading seed data..."

  # Load degree programs
  load(Rails.root.join("db/seeds/degree_programs.rb")) if Rails.root.join("db/seeds/degree_programs.rb").exist?

  # Load transfer universities
  load(Rails.root.join("db/seeds/transfer_universities.rb")) if Rails.root.join("db/seeds/transfer_universities.rb").exist?

  Rails.logger.debug "Seed data loaded successfully!"
end
