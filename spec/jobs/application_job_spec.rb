# frozen_string_literal: true

require "rails_helper"

RSpec.describe ApplicationJob do
  before do
    stub_const("RecordArgumentJob", Class.new(described_class) do
      def perform(_user)
        raise "the job ran"
      end
    end)
  end

  it "discards a job whose record was deleted before the job ran" do
    user    = create(:user)
    payload = RecordArgumentJob.new(user).serialize
    user.destroy!

    expect { ActiveJob::Base.execute(payload) }.not_to raise_error
  end

  it "still runs a job whose record exists" do
    user    = create(:user)
    payload = RecordArgumentJob.new(user).serialize

    expect { ActiveJob::Base.execute(payload) }.to raise_error(RuntimeError, "the job ran")
  end
end
