# frozen_string_literal: true

module Catalog
  # Banner sends a section number with leading zeros ("01") in some answers
  # and without them in others, so every import stores it without them. A
  # section number of only zeros is "0".
  module SectionNumber
    def self.normalize(value)
      return nil if value.blank?

      value.to_s.gsub(/^0+/, "").presence || "0"
    end
  end
end
