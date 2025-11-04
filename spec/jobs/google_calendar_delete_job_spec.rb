require 'rails_helper'

RSpec.describe GoogleCalendarDeleteJob, type: :job do
  describe 'queue assignment' do
    it 'is assigned to the high_priority queue' do
      expect(described_class.new.queue_name).to eq('high_priority')
    end
  end

  describe '#perform' do
    let(:calendar_id) { 'test_calendar_id@group.calendar.google.com' }

    it 'calls GoogleCalendarService#delete_calendar with the correct calendar_id' do
      service_double = instance_double(GoogleCalendarService)
      allow(GoogleCalendarService).to receive(:new).and_return(service_double)
      allow(service_double).to receive(:delete_calendar).with(calendar_id)

      described_class.perform_now(calendar_id)

      expect(GoogleCalendarService).to have_received(:new)
      expect(service_double).to have_received(:delete_calendar).with(calendar_id)
    end
  end
end
