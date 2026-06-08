# frozen_string_literal: true

# Processes an uploaded finals schedule PDF for a given term.
# Accepts raw PDF binary content rather than a FinalsSchedule model record,
# since this app does not have a FinalsSchedule model.
class FinalsScheduleProcessJob < ApplicationJob
  queue_as :default

  limits_concurrency to: 1, key: ->(term_uid, _pdf_content) { "finals_schedule_process_#{term_uid}" }

  def perform(term_uid, pdf_content)
    term = Term.find_by(uid: term_uid)

    unless term
      Rails.logger.error("FinalsScheduleProcessJob: term #{term_uid} not found")
      return
    end

    result = FinalsScheduleParserService.call(pdf_content: pdf_content, term: term)

    Rails.logger.info({
      message: "FinalsScheduleProcessJob completed",
      term_uid: term_uid,
      term_name: term.name,
      result: result
    }.to_json)

    result
  rescue => e
    Rails.logger.error("Failed to process finals schedule for term #{term_uid}: #{e.message}")
    Rails.logger.error(e.backtrace.first(10).join("\n"))
    raise
  end
end
