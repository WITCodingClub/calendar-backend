# frozen_string_literal: true

require "rails_helper"

RSpec.describe DegreeRequirements::RequestPacer do
  it "does not wait before the first request" do
    pacer = described_class.new(5)
    allow(pacer).to receive(:sleep)

    pacer.wait

    expect(pacer).not_to have_received(:sleep)
  end

  it "waits out the rest of the delay before the next request" do
    pacer = described_class.new(5)
    allow(pacer).to receive(:sleep)

    pacer.wait
    pacer.wait

    expect(pacer).to have_received(:sleep).with(a_value_between(4, 5))
  end

  it "never waits with no delay" do
    pacer = described_class.new(0)
    allow(pacer).to receive(:sleep)

    2.times { pacer.wait }

    expect(pacer).not_to have_received(:sleep)
  end
end
