# frozen_string_literal: true

module Catalog
  # Raised when a caller sends a filter value the catalog cannot use. Every
  # query object raises a subclass, and the public API turns it into a 400.
  class FilterError < StandardError; end
end
