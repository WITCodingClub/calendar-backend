# frozen_string_literal: true

require "rails_helper"

RSpec.describe McpTools::GetSection do
  let(:user) { create(:user) }
  let(:course) { create(:course) }

  def call(**arguments) = described_class.call(server_context: mcp_context(user), **arguments)

  it "gets a section by CRN with its final exam" do
    create(:final_exam, term: course.term, crn: course.crn, course: course)

    result = call(crn: course.crn, term_uid: course.term.uid)

    expect(result.structured_content).to include(crn: course.crn)
    expect(result.structured_content[:final_exam]).to include(date: Date.new(2026, 12, 17))
  end

  it "finds a cancelled section, the same as the REST API" do
    course.update!(status: :cancelled)

    expect(call(crn: course.crn, term_uid: course.term.uid).error?).to be(false)
  end

  describe "the Banner refresh" do
    around do |example|
      cache = Rails.cache
      Rails.cache = ActiveSupport::Cache::MemoryStore.new
      example.run
    ensure
      Rails.cache = cache
    end

    it "queues a refresh of a section whose Banner data is old, one time" do
      course.update!(banner_synced_at: 37.hours.ago)

      expect { call(crn: course.crn, term_uid: course.term.uid) }.to have_enqueued_job(Catalog::SectionRefreshJob).with([ course.id ])
      expect { call(crn: course.crn, term_uid: course.term.uid) }.not_to have_enqueued_job(Catalog::SectionRefreshJob)
    end

    it "does not queue a refresh of a section that Banner gave recently" do
      course.update!(banner_synced_at: 12.hours.ago)

      expect { call(crn: course.crn, term_uid: course.term.uid) }.not_to have_enqueued_job(Catalog::SectionRefreshJob)
    end

    it "does not queue a refresh of a section in a past term, which the nightly sync leaves out" do
      course.term # the current term
      past = create(:course, term: create(:term, year: 2020), banner_synced_at: nil)

      expect { call(crn: past.crn, term_uid: past.term.uid) }.not_to have_enqueued_job(Catalog::SectionRefreshJob)
    end

    it "does not queue a refresh of a cancelled section" do
      course.update!(banner_synced_at: 37.hours.ago, status: :cancelled)

      expect { call(crn: course.crn, term_uid: course.term.uid) }.not_to have_enqueued_job(Catalog::SectionRefreshJob)
    end

    it "queues the section again on the next call when the queue failed" do
      course.update!(banner_synced_at: 37.hours.ago)
      allow(Rails.error).to receive(:report)
      allow(Catalog::SectionRefreshJob).to receive(:perform_later).and_raise(StandardError, "queue down")
      call(crn: course.crn, term_uid: course.term.uid)
      allow(Catalog::SectionRefreshJob).to receive(:perform_later).and_call_original

      expect { call(crn: course.crn, term_uid: course.term.uid) }.to have_enqueued_job(Catalog::SectionRefreshJob).with([ course.id ])
    end

    it "still answers when the refresh fails, and reports the error" do
      course.update!(banner_synced_at: 37.hours.ago)
      allow(Catalog::SectionRefreshJob).to receive(:perform_later).and_raise(StandardError, "queue down")
      allow(Rails.error).to receive(:report)

      expect(call(crn: course.crn, term_uid: course.term.uid).error?).to be(false)
      expect(Rails.error).to have_received(:report).with(an_instance_of(StandardError), handled: true, context: { user_id: user.id })
    end
  end

  it "gives the Banner pages to read when the data is old" do
    expect(described_class.description_value).to include("getEnrollmentInfo?term=<term_uid>&courseReferenceNumber=<crn>",
                                                          "getFacultyMeetingTimes?term=<term_uid>&courseReferenceNumber=<crn>")
  end

  it "returns a tool error for an unknown CRN" do
    result = call(crn: 1, term_uid: course.term.uid)

    expect(result.error?).to be(true)
    expect(result.content.first[:text]).to eq("No section with CRN 1 in term #{course.term.uid}")
  end
end
