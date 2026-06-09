# frozen_string_literal: true

class FinalsScheduleProcessJob < ApplicationJob
  queue_as :default

  limits_concurrency to: 1, key: ->(finals_schedule) { "finals_schedule_process_#{finals_schedule.term_id}" }

  def perform(finals_schedule)
    finals_schedule.update!(status: :processing)

    pdf_content = finals_schedule.pdf_file.download
    result = FinalsScheduleParserService.call(pdf_content: pdf_content, term: finals_schedule.term)

    finals_schedule.update!(
      status:       :completed,
      processed_at: Time.current,
      stats:        result.slice(:total, :created, :updated, :linked, :orphan, :rooms_created),
      error_message: result[:errors].any? ? result[:errors].join("\n") : nil
    )

    finals_schedule.trigger_calendar_resyncs_for_term

    Rails.logger.info({
      message:  "FinalsScheduleProcessJob completed",
      term_uid: finals_schedule.term.uid,
      result:   result
    }.to_json)
  rescue => e
    finals_schedule.update!(
      status:        :failed,
      processed_at:  Time.current,
      error_message: e.message
    )
    Rails.logger.error("FinalsScheduleProcessJob failed for term #{finals_schedule.term_id}: #{e.message}")
    raise
  end
end
