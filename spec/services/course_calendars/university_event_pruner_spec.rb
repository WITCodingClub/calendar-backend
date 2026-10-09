# frozen_string_literal: true

require "rails_helper"

RSpec.describe CourseCalendars::UniversityEventPruner do
  subject(:pruner) { described_class.new(user) }

  let(:user)     { create(:user) }
  let(:calendar) { create(:course_calendar, oauth_credential: create(:oauth_credential, user: user)) }
  let(:config)   { user.user_extension_config }
  let(:service)  { instance_double(GoogleCalendar::Provider, course_calendar: calendar) }

  def synced_event(category)
    event = create(:university_calendar_event, category: category, all_day: true,
                                               start_time: 2.months.ago, end_time: 2.months.ago + 1.day)
    create(:calendar_event, :for_university_event, course_calendar: calendar,
                                                   university_calendar_event: event, end_time: event.end_time)
  end

  let!(:holiday_row)      { synced_event("holiday") }
  let!(:registration_row) { synced_event("registration") }

  before do
    allow(service).to receive(:delete_events) { |rows| rows.size }
    config.update!(sync_university_events: true, university_event_categories: %w[registration])
  end

  describe "#prune_with" do
    it "deletes nothing when the user still wants every event" do
      expect(pruner.prune_with(service)).to eq(0)
      expect(service).not_to have_received(:delete_events)
    end

    it "deletes the events of a category the user unselected and keeps holidays" do
      config.update!(university_event_categories: %w[deadline])

      expect(pruner.prune_with(service)).to eq(1)
      expect(service).to have_received(:delete_events).with([ registration_row ])
    end

    it "deletes every non-holiday event when university event sync is off" do
      config.update!(sync_university_events: false)

      pruner.prune_with(service)

      expect(service).to have_received(:delete_events).with([ registration_row ])
    end

    it "returns zero when the provider has no calendar" do
      no_calendar = instance_double(GoogleCalendar::Provider, course_calendar: nil)

      expect(pruner.prune_with(no_calendar)).to eq(0)
    end
  end

  describe "#wanted_ids" do
    it "returns holidays and the selected categories" do
      ids = [ holiday_row, registration_row ].map(&:university_calendar_event_id)

      expect(pruner.wanted_ids(ids)).to match_array(ids)
    end

    it "returns no ids for no candidates" do
      expect(pruner.wanted_ids([])).to eq([])
    end
  end

  describe "#call" do
    it "adds up the deletions of every provider" do
      config.update!(sync_university_events: false)
      allow(CourseCalendars::Providers).to receive(:services_for).with(user).and_return([ service, service ])

      expect(pruner.call).to eq(2)
    end
  end
end
