require 'rails_helper'

RSpec.describe CourseProcessorJob, type: :job do
  describe 'queue assignment' do
    it 'is assigned to the high queue' do
      expect(described_class.new.queue_name).to eq('high')
    end
  end

  describe '#perform' do
    let(:user) { create(:user) }
    let(:courses) do
      [
        {
          crn: "12345",
          term: "202501",
          courseNumber: "101",
          start: "2025-01-15",
          end: "2025-05-15"
        }
      ]
    end

    it 'calls CourseProcessorService with the correct arguments' do
      service_double = instance_double(CourseProcessorService)
      allow(CourseProcessorService).to receive(:new).with(courses, user).and_return(service_double)
      allow(service_double).to receive(:call)

      described_class.perform_now(courses, user.id)

      expect(CourseProcessorService).to have_received(:new).with(courses, user)
      expect(service_double).to have_received(:call)
    end

    it 'finds the user by id' do
      allow(User).to receive(:find).and_call_original
      allow_any_instance_of(CourseProcessorService).to receive(:call)

      described_class.perform_now(courses, user.id)

      expect(User).to have_received(:find).with(user.id)
    end
  end
end
