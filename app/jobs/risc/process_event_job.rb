# frozen_string_literal: true

module Risc
  class ProcessEventJob < ApplicationJob
    queue_as :high

    retry_on StandardError, wait: :polynomially_longer, attempts: 3
    # Google's config or JWKS was down. The webhook already answered 2xx, so the
    # job is the only retry. A later declaration wins over StandardError above.
    retry_on Risc::Validator::FetchError, wait: :polynomially_longer, attempts: 5
    discard_on Risc::Validator::ValidationError

    # The handler could not record the event at all. Raising lets retry_on try
    # again, and the job executor reports the last failure.
    class EventNotRecorded < StandardError; end

    def perform(token)
      validation_service = Risc::Validator.new
      decoded_token = validation_service.validate_and_decode(token)
      event_data    = validation_service.extract_event_data(decoded_token)

      # Skip only a finished event. One that a failed attempt left unprocessed
      # has to run again, or the retry does nothing.
      if SecurityEvent.processed.exists?(jti: event_data[:jti])
        Rails.logger.info("RISC event already processed: #{event_data[:jti]}")
        return
      end

      result = Risc::EventHandler.new(event_data).process
      Rails.logger.info("RISC event processed: #{result}")
      return if result[:success]

      # A failure that left a processed row was already reported by the
      # handler. One that left no row would vanish without a trace.
      return if SecurityEvent.processed.exists?(jti: event_data[:jti])

      raise EventNotRecorded, "RISC event #{event_data[:jti]} was not recorded: #{result[:error]}"
    end
  end
end
