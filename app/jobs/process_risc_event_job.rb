# frozen_string_literal: true

# Background job for processing Google RISC security events
# Validates and handles security event tokens asynchronously
class ProcessRiscEventJob < ApplicationJob
  queue_as :high

  # Retry with exponential backoff for transient errors
  retry_on StandardError, wait: :exponentially_longer, attempts: 3

  def perform(token)
    # Validate and decode the token
    validation_service = RiscValidationService.new
    decoded_token = validation_service.validate_and_decode(token)

    # Extract event data
    event_data = validation_service.extract_event_data(decoded_token)

    # Check for duplicate events using jti
    if SecurityEvent.exists?(jti: event_data[:jti])
      Rails.logger.info("RISC event already processed: #{event_data[:jti]}")
      return
    end

    # Process the event
    handler = RiscEventHandlerService.new(event_data)
    result = handler.process

    Rails.logger.info("RISC event processed: #{result}")
  rescue RiscValidationService::ValidationError => e
    # Don't retry validation errors - these are permanent failures
    Rails.logger.error("RISC validation error: #{e.message}")
    raise # This will be logged but not retried
  rescue => e
    Rails.logger.error("Error processing RISC event: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n"))
    raise # This will trigger retry logic
  end

end
