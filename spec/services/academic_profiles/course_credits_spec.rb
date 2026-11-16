# frozen_string_literal: true

require "rails_helper"

RSpec.describe AcademicProfiles::CourseCredits do
  let(:details) { instance_double(AcademicProfiles::CourseDetails) }
  let(:credits) { described_class.new(details) }
  let(:taken) { Struct.new(:key, :credits) }

  before do
    allow(details).to receive(:for).and_return(credit_hours: nil)
    allow(details).to receive(:for).with([ "WDGT", 1000 ]).and_return(credit_hours: 3)
  end

  it "counts a taken course with its section credits, else its catalog credits, else 0" do
    expect(credits.of(taken.new([ "WDGT", 1000 ], 4))).to eq(4)
    expect(credits.of(taken.new([ "WDGT", 1000 ], nil))).to eq(3)
    expect(credits.of(taken.new([ "WDGT", 9999 ], nil))).to eq(0)
  end

  it "estimates a course still to take with its catalog credits, else the default" do
    expect(credits.of_key([ "WDGT", 1000 ])).to eq(3)
    expect(credits.of_key([ "WDGT", 9999 ])).to eq(described_class::DEFAULT)
  end
end
