# frozen_string_literal: true

class CatalogImportJob < ApplicationJob
  queue_as :low

  def perform(catalog_courses)
    CatalogImportService.new(catalog_courses).call
  end
end
