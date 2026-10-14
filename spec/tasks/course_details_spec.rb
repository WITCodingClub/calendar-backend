# frozen_string_literal: true

require "rails_helper"
require "rake"

RSpec.describe "catalog:backfill_course_details" do
  include ActiveJob::TestHelper

  before(:all) { Rails.application.load_tasks if Rake::Task.tasks.empty? }

  def run_task
    task = Rake::Task["catalog:backfill_course_details"]
    task.reenable
    task.invoke
  end

  it "seeds every course and enqueues a sync for each term with courses, newest first" do
    older = create(:term, uid: 202620, year: 2026, season: :spring)
    newer = create(:term, uid: 202720, year: 2027, season: :spring)
    create(:term, uid: 202730, year: 2027, season: :summer)
    create(:course, term: older)
    create(:course, term: newer)

    expect { run_task }.to output(/Seeded 2 courses.*202720, 202620/m).to_stdout

    expect(CatalogCourse.count).to eq(2)
    expect(enqueued_jobs.select { |job| job["job_class"] == "Catalog::CourseDetailsSyncJob" }.map { |job| job["arguments"] })
      .to eq([ [ 202720 ], [ 202620 ] ])
  end
end
