# frozen_string_literal: true

module McpPlatforms
  # Keeps the copy of OpenAI's ChatGPT connector ranges fresh (McpPlatforms).
  # OpenAI says the list changes and asks for regular fetches. A failed fetch
  # raises, so the job executor reports it, and the old copy stays.
  class RefreshOpenaiRangesJob < ApplicationJob
    queue_as :low

    def perform
      ranges = OpenaiRangesClient.new.fetch
      McpPlatforms.store_openai_ranges(ranges)

      Rails.logger.info "[McpPlatforms::RefreshOpenaiRangesJob] Stored #{ranges.size} OpenAI ranges"
    end
  end
end
