# frozen_string_literal: true

require "rails_helper"

RSpec.describe CourseCalendar, type: :model do
  subject { create(:course_calendar) }

  it { is_expected.to belong_to(:oauth_credential) }
  it { is_expected.to have_many(:calendar_events).dependent(:destroy) }
  it { is_expected.to have_one(:user).through(:oauth_credential) }

  it { is_expected.to define_enum_for(:provider).with_values(google: "google", microsoft: "microsoft").backed_by_column_of_type(:string) }

  it { is_expected.to validate_presence_of(:external_calendar_id) }
  it { is_expected.to validate_uniqueness_of(:external_calendar_id).scoped_to(:provider) }
  it { is_expected.to validate_uniqueness_of(:oauth_credential_id) }

  it "uses the provider-neutral calendars table" do
    expect(described_class.table_name).to eq("calendars")
  end

  describe "remote deletion on destroy" do
    include ActiveJob::TestHelper

    it "deletes a Google calendar through the service account job" do
      calendar = create(:course_calendar, external_calendar_id: "cal@group.calendar.google.com")

      expect { calendar.destroy }.to have_enqueued_job(GoogleCalendarDeleteJob).with("cal@group.calendar.google.com")
    end

    it "deletes a Microsoft calendar with the owner's credential" do
      calendar = create(:course_calendar, :microsoft)

      expect { calendar.destroy }
        .to have_enqueued_job(MicrosoftGraphCalendarDeleteJob).with(calendar.oauth_credential_id, calendar.external_calendar_id)
    end
  end
end
