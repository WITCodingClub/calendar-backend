# frozen_string_literal: true

require "rails_helper"

RSpec.describe SecurityEvent, type: :model do
  subject { create(:security_event) }

  it { is_expected.to belong_to(:user).optional }
  it { is_expected.to belong_to(:oauth_credential).optional }

  it { is_expected.to validate_presence_of(:jti) }
  it { is_expected.to validate_uniqueness_of(:jti) }
  it { is_expected.to validate_presence_of(:event_type) }
  it { is_expected.to validate_presence_of(:google_subject) }
end
