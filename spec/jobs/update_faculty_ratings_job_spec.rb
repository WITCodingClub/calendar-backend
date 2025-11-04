require 'rails_helper'

RSpec.describe UpdateFacultyRatingsJob, type: :job do
  describe 'queue assignment' do
    it 'is assigned to the low queue' do
      expect(described_class.new.queue_name).to eq('low')
    end
  end

  pending "add some examples to (or delete) #{__FILE__}"
end
