# frozen_string_literal: true

# Data that the extension collects from a student's Brightspace (D2L) account.
# See docs/brightspace.md for the API contract.
module Brightspace
  def self.table_name_prefix
    "brightspace_"
  end

  # The extension sends these sections for each class. A section that the
  # payload leaves out stays as it is.
  SECTIONS = %w[assignments announcements grades syllabus].freeze

  def self.enabled_for?(user)
    Flipper.enabled?(FlipperFlags::BRIGHTSPACE, user)
  end
end
