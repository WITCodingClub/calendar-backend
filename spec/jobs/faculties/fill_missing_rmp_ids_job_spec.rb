# frozen_string_literal: true

require "rails_helper"

RSpec.describe Faculties::FillMissingRmpIdsJob, type: :job do
  include ActiveSupport::Testing::TimeHelpers

  around { |example| travel_to(Date.new(2026, 10, 1)) { example.run } }

  let(:current_term) { create(:term, year: 2026, season: :fall) }

  def teaching(faculty, term = current_term)
    create(:course_faculty, faculty: faculty, course: create(:course, term: term))
    faculty
  end

  it "enqueues Faculties::UpdateRatingsJob for each current faculty with no rmp_id" do
    faculty = teaching(create(:faculty, rmp_id: nil))

    expect { described_class.perform_now }
      .to have_enqueued_job(Faculties::UpdateRatingsJob).with(faculty.id).exactly(:once)
  end

  it "does not search RateMyProfessor inside the job" do
    teaching(create(:faculty, rmp_id: nil))
    allow(Faculties::UpdateRatingsJob).to receive(:perform_now)

    described_class.perform_now

    expect(Faculties::UpdateRatingsJob).not_to have_received(:perform_now)
  end

  it "skips faculty who already have an rmp_id" do
    teaching(create(:faculty, rmp_id: "already-has-one"))

    expect { described_class.perform_now }.not_to have_enqueued_job(Faculties::UpdateRatingsJob)
  end

  it "skips faculty who teach only in past terms" do
    teaching(create(:faculty, rmp_id: nil), create(:term, year: 2025, season: :spring))
    current_term

    expect { described_class.perform_now }.not_to have_enqueued_job(Faculties::UpdateRatingsJob)
  end

  it "skips faculty who teach no courses" do
    create(:faculty, rmp_id: nil)
    current_term

    expect { described_class.perform_now }.not_to have_enqueued_job(Faculties::UpdateRatingsJob)
  end
end
