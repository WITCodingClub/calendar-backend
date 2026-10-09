# frozen_string_literal: true

require "rails_helper"

RSpec.describe Courses::ProcessTermJob do
  let(:user) { create(:user) }
  let(:term) { create(:term) }
  let(:courses) { [ { "crn" => "11111", "term" => term.uid.to_s } ] }

  def stub_service(&block)
    service = instance_double(Courses::Processor)
    allow(service).to receive(:call, &block)
    allow(Courses::Processor).to receive(:new).and_return(service)
    service
  end

  def status_row
    TermProcessingStatus.find_by(user: user, term: term)
  end

  it "processes the courses for the user" do
    service = stub_service { [ { id: 1 } ] }

    described_class.perform_now(user, term, courses)

    expect(Courses::Processor).to have_received(:new).with(courses, user)
    expect(service).to have_received(:call)
  end

  it "marks the term as processing while the service runs" do
    seen = nil
    stub_service do
      seen = status_row.status
      [ { id: 1 } ]
    end

    described_class.perform_now(user, term, courses)

    expect(seen).to eq("processing")
  end

  it "marks the term as failed when Banner returns no details for any course" do
    stub_service { [] }

    described_class.perform_now(user, term, courses)

    expect(status_row).to have_attributes(status: "failed", error_code: "no_course_details")
  end

  it "marks the term as failed and discards the job when the term does not exist" do
    stub_service { raise Courses::InvalidTermError.new(term.uid) }

    expect { described_class.perform_now(user, term, courses) }.not_to raise_error
    expect(status_row).to have_attributes(status: "failed", error_code: "term_not_found")
  end

  it "retries the job when Banner fails" do
    stub_service { raise Catalog::LeopardWebClient::RequestError.new("down", status: 503) }

    expect { described_class.perform_now(user, term, courses) }.to have_enqueued_job(described_class)
    expect(status_row.status).to eq("processing")
  end

  it "marks the term as failed when Banner fails on every retry" do
    stub_service { raise Catalog::LeopardWebClient::RequestError.new("down", status: 503) }

    job = described_class.new(user, term, courses)
    2.times { job.perform_now }
    expect(status_row.status).to eq("processing")

    expect { job.perform_now }.to raise_error(Catalog::LeopardWebClient::RequestError)

    expect(status_row).to have_attributes(status: "failed", error_code: "banner_unavailable")
  end

  it "marks the term as failed and raises an unexpected error, so the job shows in the failed jobs" do
    stub_service { raise ArgumentError, "bug" }

    expect { described_class.perform_now(user, term, courses) }.to raise_error(ArgumentError, "bug")
    expect(status_row).to have_attributes(status: "failed", error_code: "internal_error")
  end
end
