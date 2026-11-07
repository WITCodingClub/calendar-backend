# frozen_string_literal: true

require "rails_helper"

RSpec.describe Faculties::RefreshRatingsJob, type: :job do
  include ActiveSupport::Testing::TimeHelpers

  around { |example| travel_to(Date.new(2026, 10, 1)) { example.run } }

  let(:current_term) { create(:term, year: 2026, season: :fall) }

  def teaching(faculty, term = current_term)
    create(:course_faculty, faculty: faculty, course: create(:course, term: term))
    faculty
  end

  # Records the jobs that one run enqueues, not the ones from earlier examples.
  def run_and_collect_faculty_ids
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear
    described_class.perform_now
    enqueued_faculty_ids
  end

  def enqueued_faculty_ids
    ActiveJob::Base.queue_adapter.enqueued_jobs
                   .select { |job| job[:job] == Faculties::UpdateRatingsJob }
                   .map { |job| job[:args].first }
  end

  it "enqueues one Faculties::UpdateRatingsJob for each current faculty, with or without an rmp_id" do
    missing = teaching(create(:faculty, rmp_id: nil))
    linked  = teaching(create(:faculty, rmp_id: "already-has-one"))

    expect(run_and_collect_faculty_ids).to contain_exactly(missing.id, linked.id)
  end

  it "enqueues the faculty with no rmp_id first" do
    linked  = teaching(create(:faculty, rmp_id: "already-has-one"))
    missing = teaching(create(:faculty, rmp_id: nil))

    expect(run_and_collect_faculty_ids).to eq([ missing.id, linked.id ])
  end

  it "does not search RateMyProfessor inside the job" do
    teaching(create(:faculty, rmp_id: nil))
    allow(Faculties::UpdateRatingsJob).to receive(:perform_now)

    described_class.perform_now

    expect(Faculties::UpdateRatingsJob).not_to have_received(:perform_now)
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

  it "skips the run while an earlier refresh has jobs left" do
    teaching(create(:faculty, rmp_id: nil))
    SolidQueue::Batch.create!(description: described_class::BATCH_DESCRIPTION)

    expect { described_class.perform_now }.not_to have_enqueued_job(Faculties::UpdateRatingsJob)
  end

  describe "batch" do
    it "runs the faculty with no rmp_id first, and holds the rest behind the concurrency limit" do
      linked  = teaching(create(:faculty, rmp_id: "already-has-one"))
      missing = teaching(create(:faculty, rmp_id: nil))
      previous = Faculties::UpdateRatingsJob.queue_adapter
      Faculties::UpdateRatingsJob.queue_adapter = :solid_queue

      described_class.perform_now

      ids = ->(executions) { executions.map { |execution| execution.job.arguments["arguments"].first } }
      expect(ids.call(SolidQueue::ReadyExecution.all)).to eq([ missing.id ])
      expect(ids.call(SolidQueue::BlockedExecution.all)).to eq([ linked.id ])
    ensure
      Faculties::UpdateRatingsJob.queue_adapter = previous
    end

    it "puts the rating jobs in one batch, which waits for them" do
      faculty = teaching(create(:faculty, rmp_id: nil))
      # The :test adapter gives a job no batch, so the rating jobs go to the
      # Solid Queue tables here, as in production.
      previous = Faculties::UpdateRatingsJob.queue_adapter
      Faculties::UpdateRatingsJob.queue_adapter = :solid_queue

      described_class.perform_now

      batch = SolidQueue::Batch.last
      expect(batch.metadata[:faculty_count]).to eq(1)
      expect(batch.jobs.pluck(:class_name, :arguments).map { |name, args| [ name, args["arguments"] ] })
        .to eq([ [ "Faculties::UpdateRatingsJob", [ faculty.id ] ] ])
      expect(SolidQueue::Job.where(class_name: "Embeddings::BackfillJob")).to be_empty
    ensure
      Faculties::UpdateRatingsJob.queue_adapter = previous
    end

    it "embeds the reviews when the batch finishes" do
      teaching(create(:faculty, rmp_id: nil))

      described_class.perform_now

      # The :test adapter does not run the rating jobs, so the batch has no
      # Solid Queue jobs and finishes at once.
      callback = SolidQueue::Job.find_by!(class_name: "Embeddings::BackfillJob")
      expect(callback.arguments["arguments"]).to eq([ "RmpRating" ])
    end
  end

  it "runs a job queued under the old class name" do
    teaching(create(:faculty, rmp_id: nil))
    old_job = Faculties::RefreshRatingsJob.new.serialize.merge("job_class" => "Faculties::FillMissingRmpIdsJob")

    expect { ActiveJob::Base.execute(old_job) }.to have_enqueued_job(Faculties::UpdateRatingsJob)
  end
end
