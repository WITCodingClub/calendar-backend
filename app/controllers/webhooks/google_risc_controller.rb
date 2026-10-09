# frozen_string_literal: true

module Webhooks
  class GoogleRiscController < ApplicationController
    skip_before_action :verify_authenticity_token

    def create
      token = extract_token_from_request

      if token.blank?
        render json: { error: "Security event token missing" }, status: :bad_request
        return
      end

      Risc::ProcessEventJob.perform_later(token)
      head :accepted
    rescue => e
      Rails.error.report(e, handled: true)
      head :bad_request
    end

    private

    def extract_token_from_request
      request.body.rewind
      body = request.body.read

      begin
        parsed = JSON.parse(body)
        parsed["token"] || parsed["jwt"] || body
      rescue JSON::ParserError
        body
      end
    end
  end
end
