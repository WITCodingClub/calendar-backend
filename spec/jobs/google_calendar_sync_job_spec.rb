require 'rails_helper'

RSpec.describe GoogleCalendarSyncJob, type: :job do
  describe '#perform' do
    let(:user) { create(:user) }

    it 'calls sync_course_schedule on the user' do
      allow_any_instance_of(User).to receive(:sync_course_schedule)

      described_class.perform_now(user)

      expect(user).to have_received(:sync_course_schedule)
    end
  end
end
