require 'rails_helper'

RSpec.describe GoogleCalendarCreateJob, type: :job do
  describe '#perform' do
    let(:user) { create(:user) }

    it 'calls GoogleCalendarService#create_or_get_course_calendar' do
      service_double = instance_double(GoogleCalendarService)
      allow(GoogleCalendarService).to receive(:new).with(user).and_return(service_double)
      allow(service_double).to receive(:create_or_get_course_calendar)

      described_class.perform_now(user.id)

      expect(GoogleCalendarService).to have_received(:new).with(user)
      expect(service_double).to have_received(:create_or_get_course_calendar)
    end

    it 'finds the user by id' do
      allow(User).to receive(:find).and_call_original
      allow_any_instance_of(GoogleCalendarService).to receive(:create_or_get_course_calendar)

      described_class.perform_now(user.id)

      expect(User).to have_received(:find).with(user.id)
    end
  end
end
