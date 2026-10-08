# frozen_string_literal: true

# Imported rows are kept after Brightspace stops listing them. A complete
# section sets removed_at, and the row comes back when a later sync lists it.
module Brightspace
  module Removable
    extend ActiveSupport::Concern

    included do
      scope :not_removed, -> { where(removed_at: nil) }
      scope :removed,     -> { where.not(removed_at: nil) }
    end

    def removed? = removed_at.present?
  end
end
