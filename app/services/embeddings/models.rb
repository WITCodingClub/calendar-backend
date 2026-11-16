# frozen_string_literal: true

module Embeddings
  # The models that carry a vector (Embeddable), with the rows of each that
  # get one. Embeddings::BackfillJob scans them, Embeddings::GenerateJob
  # embeds them, and lib/tasks/embeddings.rake reports on them. A new model
  # goes here and nowhere else.
  module Models
    # Reviews are the largest table by far, so they come last.
    SCOPES = {
      "CatalogCourse" => -> { CatalogCourse.includes(catalog_year_courses: :catalog_year) },
      "Faculty"       => -> { Faculty.with_courses },
      "RmpRating"     => -> { RmpRating.where.not(comment: [ nil, "" ]) }
    }.freeze

    def self.names = SCOPES.keys
    def self.known?(name) = SCOPES.key?(name)
    def self.scope(name) = SCOPES.fetch(name).call
  end
end
