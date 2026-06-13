# frozen_string_literal: true

class ProcessRiscEventJob < ApplicationJob
  queue_as :high

  retry_on StandardError, wait: :exponentially_longer, attempts: 3
  discard_on RiscValidationService::ValidationError

  def perform(token)
    validation_service = RiscValidationService.new
    decoded_token = validation_service.validate_and_decode(token)
    event_data    = validation_service.extract_event_data(decoded_token)

    if SecurityEvent.exists?(jti: event_data[:jti])
      Rails.logger.info("RISC event already processed: #{event_data[:jti]}")
      return
    end

    result = RiscEventHandlerService.new(event_data).process
    Rails.logger.info("RISC event processed: #{result}")
  rescue RiscValidationService::ValidationError => e
    Rails.logger.error("RISC validation error: #{e.message}")
    raise
  rescue => e
    Rails.logger.error("Error processing RISC event: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n"))
    raise
  end
end
