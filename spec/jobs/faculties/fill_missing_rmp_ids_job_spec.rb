# frozen_string_literal: true

require "rails_helper"

RSpec.describe Faculties::FillMissingRmpIdsJob, type: :job do
  it "does nothing when every faculty with courses already has an rmp_id" do
    faculty = create(:faculty, rmp_id: "already-has-one")
    create(:course_faculty, faculty: faculty)

    expect(Faculties::UpdateRatingsJob).not_to receive(:perform_now)

    described_class.perform_now
  end

  it "runs Faculties::UpdateRatingsJob for every faculty with courses and no rmp_id" do
    faculty = create(:faculty, rmp_id: nil)
    create(:course_faculty, faculty: faculty)

    allow_any_instance_of(described_class).to receive(:sleep)
    allow(Faculties::UpdateRatingsJob).to receive(:perform_now) do |faculty_id|
      Faculty.find(faculty_id).update!(rmp_id: "found-it")
    end

    described_class.perform_now

    expect(Faculties::UpdateRatingsJob).to have_received(:perform_now).with(faculty.id)
    expect(faculty.reload.rmp_id).to eq("found-it")
  end

  it "keeps processing later faculty when one raises an error" do
    faculty_a = create(:faculty, rmp_id: nil)
    create(:course_faculty, faculty: faculty_a)
    faculty_b = create(:faculty, rmp_id: nil)
    create(:course_faculty, faculty: faculty_b)

    allow_any_instance_of(described_class).to receive(:sleep)
    call_count = 0
    allow(Faculties::UpdateRatingsJob).to receive(:perform_now) do |_faculty_id|
      call_count += 1
      raise "RateMyProfessors is down" if call_count == 1
    end

    expect { described_class.perform_now }.not_to raise_error
    expect(Faculties::UpdateRatingsJob).to have_received(:perform_now).twice
  end

  it "does not process faculty who teach no courses" do
    create(:faculty, rmp_id: nil)

    expect(Faculties::UpdateRatingsJob).not_to receive(:perform_now)

    described_class.perform_now
  end
end
