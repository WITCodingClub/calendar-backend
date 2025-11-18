# frozen_string_literal: true

require "rails_helper"

RSpec.describe GoogleCalendarCreateJob do
  describe "queue assignment" do
    it "is assigned to the high queue" do
      expect(described_class.new.queue_name).to eq("high")
    end
  end

  describe "#perform" do
    let(:user) { create(:user) }

    it "calls GoogleCalendarService#create_or_get_course_calendar" do
      service_double = instance_double(GoogleCalendarService)
      allow(GoogleCalendarService).to receive(:new).with(user).and_return(service_double)
      allow(service_double).to receive(:create_or_get_course_calendar)
      allow(user).to receive(:sync_course_schedule)
      allow(User).to receive(:find_by).and_return(user)

      described_class.perform_now(user.id)

      expect(GoogleCalendarService).to have_received(:new).with(user)
      expect(service_double).to have_received(:create_or_get_course_calendar)
    end

    it "finds the user by id" do
      allow(User).to receive(:find_by).and_call_original
      allow_any_instance_of(GoogleCalendarService).to receive(:create_or_get_course_calendar)
      # Need to stub sync_course_schedule before the job runs
      allow_any_instance_of(User).to receive(:sync_course_schedule)

      described_class.perform_now(user.id)

      expect(User).to have_received(:find_by).with(id: user.id)
    end
  end
end
