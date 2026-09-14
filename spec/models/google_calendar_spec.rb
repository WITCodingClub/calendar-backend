# frozen_string_literal: true

require "rails_helper"

RSpec.describe GoogleCalendar, type: :model do
  subject { create(:google_calendar) }

  it { is_expected.to belong_to(:oauth_credential) }
  it { is_expected.to have_many(:google_calendar_events).dependent(:destroy) }
  it { is_expected.to have_one(:user).through(:oauth_credential) }

  it { is_expected.to validate_presence_of(:google_calendar_id) }
  it { is_expected.to validate_uniqueness_of(:google_calendar_id) }
  it { is_expected.to validate_uniqueness_of(:oauth_credential_id) }
end
