# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProcessTermCoursesJob do
  let(:user) { create(:user) }
  let(:courses) { [ { "crn" => "11111", "term" => "202710" } ] }

  it "processes the courses for the user" do
    service = instance_double(CourseProcessorService, call: [])
    allow(CourseProcessorService).to receive(:new).and_return(service)

    described_class.perform_now(user, courses)

    expect(CourseProcessorService).to have_received(:new).with(courses, user)
    expect(service).to have_received(:call)
  end

  it "discards the job when the term does not exist" do
    service = instance_double(CourseProcessorService)
    allow(service).to receive(:call).and_raise(InvalidTermError.new("202710"))
    allow(CourseProcessorService).to receive(:new).and_return(service)

    expect { described_class.perform_now(user, courses) }.not_to raise_error
  end

  it "retries the job when Banner fails" do
    service = instance_double(CourseProcessorService)
    allow(service).to receive(:call).and_raise(LeopardWebService::RequestError.new("down", status: 503))
    allow(CourseProcessorService).to receive(:new).and_return(service)

    expect { described_class.perform_now(user, courses) }.to have_enqueued_job(described_class)
  end
end
