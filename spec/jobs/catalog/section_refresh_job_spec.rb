# frozen_string_literal: true

require "rails_helper"

RSpec.describe Catalog::SectionRefreshJob do
  include ActiveSupport::Testing::TimeHelpers

  let(:term) { create(:term, uid: 202710) }
  let(:course) { create(:course, crn: 12345, term: term, seats_available: 20, seats_capacity: 30, banner_synced_at: 8.hours.ago) }

  let(:details) do
    {
      title: course.title, subject: course.subject, section_number: course.section_number,
      schedule_type: "Lecture (#{course.schedule_type})", grade_mode: course.grade_mode,
      seats_available: 3, seats_capacity: 30,
      meeting_times: [
        {
          "building" => "IRAH", "building_description" => "Ira Allen Hall", "room" => "308",
          "startDate" => "09/08/2026", "endDate" => "12/15/2026",
          "startTime" => "1300", "endTime" => "1445", "days" => { "monday" => true }
        }
      ],
      faculty: []
    }
  end

  it "brings the sections up to date from Banner and records the time" do
    allow(Catalog::LeopardWebClient).to receive(:get_class_details)
      .with(term: 202710, course_reference_number: 12345).and_return(details)

    freeze_time do
      described_class.perform_now([ course.id ])

      course.reload
      expect(course.seats_available).to eq(3)
      expect(course.meeting_times.flat_map { |mt| mt.rooms.map(&:number) }).to eq([ "308" ])
      expect(course.banner_synced_at).to eq(Time.current)
    end
  end

  it "reports a section Banner fails on, keeps its old time, and goes on to the next" do
    other = create(:course, term: term, crn: 67890)
    error = Catalog::LeopardWebClient::RequestError.new("Banner answered 500", status: 500)
    allow(Catalog::LeopardWebClient).to receive(:get_class_details).and_return(details)
    allow(Catalog::LeopardWebClient).to receive(:get_class_details)
      .with(term: 202710, course_reference_number: 12345).and_raise(error)
    allow(Rails.error).to receive(:report)

    described_class.perform_now([ course.id, other.id ])

    expect(Rails.error).to have_received(:report).with(error, handled: true, context: hash_including(crn: 12345))
    expect(course.reload.banner_synced_at).to be < 7.hours.ago
    expect(other.reload.banner_synced_at).to be_present
  end

  it "stops when Banner cools down, so the job retries later" do
    allow(Catalog::LeopardWebClient).to receive(:get_class_details)
      .and_raise(Catalog::BannerThrottle::CooldownError.new(60))

    expect { described_class.perform_now([ course.id ]) }.to have_enqueued_job(described_class)
  end

  it "does nothing for sections that no longer exist" do
    allow(Catalog::LeopardWebClient).to receive(:get_class_details)

    described_class.perform_now([ 0 ])

    expect(Catalog::LeopardWebClient).not_to have_received(:get_class_details)
  end
end
