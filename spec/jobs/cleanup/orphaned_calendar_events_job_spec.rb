# frozen_string_literal: true

require "rails_helper"

RSpec.describe Cleanup::OrphanedCalendarEventsJob do
  let(:calendar) { create(:course_calendar, external_calendar_id: "google-cal-1") }

  # The model validates that an event has exactly one owner, so an orphan only
  # exists after the owner row goes away. Clear the column to simulate that.
  def create_orphan(calendar: self.calendar, **attrs)
    event = create(:calendar_event, course_calendar: calendar, **attrs)
    event.update_columns(meeting_time_id: nil) # rubocop:disable Rails/SkipsModelValidations
    event
  end

  it "keeps events that still have an owner" do
    kept = create(:calendar_event, course_calendar: calendar)

    result = described_class.perform_now

    expect(result).to eq(total: 0, deleted: 0, errors: 0)
    expect(CalendarEvent.exists?(kept.id)).to be(true)
  end

  it "deletes the row and leaves the Google event to the provider's delete job" do
    orphan = create_orphan(external_event_id: "evt-1")

    expect { described_class.perform_now }
      .to have_enqueued_job(GoogleCalendar::EventDeleteJob).with("google-cal-1", "evt-1")
    expect(CalendarEvent.exists?(orphan.id)).to be(false)
  end

  it "deletes the row and leaves the Microsoft event to the provider's delete job" do
    microsoft_calendar = create(:course_calendar, :microsoft)
    orphan = create_orphan(calendar: microsoft_calendar, external_event_id: "ms-evt-1")

    expect { described_class.perform_now }.to have_enqueued_job(MicrosoftGraph::EventDeleteJob)
    expect(CalendarEvent.exists?(orphan.id)).to be(false)
  end

  it "counts nothing and deletes nothing in a dry run" do
    orphan = create_orphan

    result = described_class.perform_now(dry_run: true)

    expect(result).to eq(total: 1, deleted: 0, errors: 0)
    expect(CalendarEvent.exists?(orphan.id)).to be(true)
  end

  it "reports an error, counts it, and goes on to the next orphan" do
    broken = create_orphan(external_event_id: "evt-1")
    fine = create_orphan(external_event_id: "evt-2")
    allow(Rails.error).to receive(:report)
    allow_any_instance_of(CalendarEvent).to receive(:destroy!).and_wrap_original do |original, *args|
      raise ActiveRecord::RecordNotDestroyed, "synthetic failure" if original.receiver.id == broken.id

      original.call(*args)
    end

    result = described_class.perform_now

    expect(result).to eq(total: 2, deleted: 1, errors: 1)
    expect(CalendarEvent.exists?(broken.id)).to be(true)
    expect(CalendarEvent.exists?(fine.id)).to be(false)
    expect(Rails.error).to have_received(:report)
      .with(an_instance_of(ActiveRecord::RecordNotDestroyed), handled: true, context: { calendar_event_id: broken.id })
  end
end
