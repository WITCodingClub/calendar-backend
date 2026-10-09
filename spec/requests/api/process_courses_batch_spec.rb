# frozen_string_literal: true

require "rails_helper"

RSpec.describe "POST /api/process_courses/batch", type: :request do
  include ActiveJob::TestHelper

  let(:user) { create(:user) }
  let(:headers) { auth_headers_for(user) }
  let!(:fall) { create(:term, uid: 202710) }
  let!(:spring) { create(:term, uid: 202720) }
  let!(:summer) { create(:term, uid: 202730) }

  let(:class_details) do
    {
      title: "Data Structures",
      subject: "COMP",
      section_number: "01",
      credit_hours: 4,
      schedule_type: "Lecture (LEC)",
      meeting_times: [
        {
          "building"  => "IRAH",
          "room"      => "112",
          "startDate" => "09/08/2026",
          "endDate"   => "12/15/2026",
          "startTime" => "1300",
          "endTime"   => "1445",
          "days"      => { "monday" => true }
        }
      ]
    }
  end

  before do
    allow(Catalog::LeopardWebClient).to receive(:get_class_details).and_return(class_details)
  end

  def term_entry(uid, crns = [ "11111" ])
    { term: uid.to_s, courses: crns.map { |crn| { crn: crn, term: uid.to_s, courseNumber: "2000" } } }
  end

  def post_batch(terms)
    post "/api/process_courses/batch", params: { terms: terms }, headers: headers, as: :json
  end

  def term_results
    response.parsed_body["terms"]
  end

  it "processes the first term now and queues the other terms" do
    expect do
      post_batch([ term_entry(202710, %w[11111 22222]), term_entry(202720), term_entry(202730) ])
    end.to have_enqueued_job(Courses::ProcessTermJob).twice

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include("user_pub" => user.public_id, "ics_url" => user.cal_url_with_extension)
    expect(term_results).to eq([
      { "term" => "202710", "status" => "processed", "course_count" => 2 },
      { "term" => "202720", "status" => "pending" },
      { "term" => "202730", "status" => "pending" }
    ])
    expect(user.enrollments.where(term: fall).count).to eq(2)
    expect(user.enrollments.where(term: spring)).not_to exist
  end

  it "enrolls the user in the queued terms when the jobs run" do
    perform_enqueued_jobs(only: Courses::ProcessTermJob) do
      post_batch([ term_entry(202710), term_entry(202720) ])
    end

    expect(user.enrollments.where(term: spring)).to exist
  end

  describe "processing status" do
    def status_of(term)
      TermProcessingStatus.find_by(user: user, term: term)
    end

    it "marks the first term processed and the queued terms pending" do
      post_batch([ term_entry(202710), term_entry(202720) ])

      expect(status_of(fall).status).to eq("processed")
      expect(status_of(spring).status).to eq("pending")
    end

    it "marks a queued term processed after its job runs" do
      perform_enqueued_jobs(only: Courses::ProcessTermJob) do
        post_batch([ term_entry(202710), term_entry(202720) ])
      end

      expect(status_of(spring).status).to eq("processed")
    end

    it "fails the first term when Banner returns no details for any course" do
      allow(Catalog::LeopardWebClient).to receive(:get_class_details).and_return(nil)

      post_batch([ term_entry(202710) ])

      expect(term_results.first).to eq(
        "term" => "202710", "status" => "failed", "error" => "No course details found for term 202710"
      )
      expect(status_of(fall)).to have_attributes(status: "failed", error_code: "no_course_details")
    end

    it "marks the first term failed when Banner is down" do
      allow(Catalog::LeopardWebClient).to receive(:get_class_details)
        .and_raise(Catalog::LeopardWebClient::RequestError.new("Banner is down", status: 503))

      post_batch([ term_entry(202710) ])

      expect(status_of(fall)).to have_attributes(status: "failed", error_code: "banner_unavailable")
    end

    it "queues the first term when a job for that term is still in flight" do
      create(:term_processing_status, user: user, term: fall, status: "processing")

      expect { post_batch([ term_entry(202710), term_entry(202720) ]) }
        .to have_enqueued_job(Courses::ProcessTermJob).with(user, fall, anything)

      expect(term_results).to eq([
        { "term" => "202710", "status" => "pending" },
        { "term" => "202720", "status" => "processed", "course_count" => 1 }
      ])
    end
  end

  it "fills in a missing course term from its entry" do
    post_batch([ { term: "202710", courses: [ { crn: "11111", courseNumber: "2000" } ] } ])

    expect(term_results.first).to include("status" => "processed")
    expect(user.enrollments.where(term: fall)).to exist
  end

  describe "partial failure" do
    it "reports a Banner failure on the first term and still queues the others" do
      allow(Catalog::LeopardWebClient).to receive(:get_class_details)
        .and_raise(Catalog::LeopardWebClient::RequestError.new("Banner is down", status: 503))

      expect { post_batch([ term_entry(202710), term_entry(202720) ]) }
        .to have_enqueued_job(Courses::ProcessTermJob).once

      expect(response).to have_http_status(:ok)
      expect(term_results).to eq([
        { "term" => "202710", "status" => "failed", "error" => "Failed to process courses" },
        { "term" => "202720", "status" => "pending" }
      ])
    end

    it "fails an unknown term and processes the next valid term now" do
      post_batch([ term_entry(209910), term_entry(202720) ])

      expect(term_results).to eq([
        { "term" => "209910", "status" => "failed", "error" => "Term 209910 not found" },
        { "term" => "202720", "status" => "processed", "course_count" => 1 }
      ])
    end

    it "fails a term that repeats in the batch" do
      post_batch([ term_entry(202710), term_entry(202710) ])

      expect(term_results.last).to eq(
        "term" => "202710", "status" => "failed", "error" => "Term 202710 appears more than once in the batch"
      )
    end

    it "fails a term with a course from another term" do
      entry = { term: "202710", courses: [ { crn: "11111", term: "202720" } ] }
      post_batch([ entry ])

      expect(term_results.first).to include("status" => "failed", "error" => "All courses in term 202710 must belong to that term")
    end

    it "fails a term with a course that has no CRN" do
      post_batch([ { term: "202710", courses: [ { courseNumber: "2000" } ] } ])

      expect(term_results.first).to include("status" => "failed", "error" => "course at index 0 missing required field: crn")
    end

    it "fails a term with no courses" do
      post_batch([ { term: "202710", courses: [] } ])

      expect(term_results.first).to include("status" => "failed", "error" => "Term 202710 has no courses")
    end

    it "fails an entry without a numeric term" do
      post_batch([ { term: "fall", courses: [ { crn: "11111" } ] }, "not an object" ])

      expect(term_results).to eq([
        { "term" => "fall", "status" => "failed", "error" => "Term entry is missing a numeric term" },
        { "term" => nil, "status" => "failed", "error" => "Each term entry must be an object" }
      ])
    end
  end

  describe "bad requests" do
    it "rejects a request without terms" do
      post_batch([])

      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body["error"]).to eq("No terms provided")
    end

    it "rejects more terms than the limit" do
      entries = Array.new(Courses::BatchProcessor::MAX_TERMS + 1) { |i| term_entry(202710 + i) }
      post_batch(entries)

      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body["error"]).to eq("A batch can have at most #{Courses::BatchProcessor::MAX_TERMS} terms")
    end

    it "rejects a request without a token" do
      post "/api/process_courses/batch", params: { terms: [ term_entry(202710) ] }, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "POST /api/process_courses" do
    it "still accepts the single-term shape" do
      post "/api/process_courses", params: { courses: term_entry(202710)[:courses] }, headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq("user_pub" => user.public_id, "ics_url" => user.cal_url_with_extension)
      expect(user.enrollments.where(term: fall)).to exist
    end
  end
end
