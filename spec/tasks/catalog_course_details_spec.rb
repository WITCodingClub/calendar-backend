# frozen_string_literal: true

require "rails_helper"
require "rake"

RSpec.describe "catalog:backfill_course_details" do
  include ActiveJob::TestHelper

  before(:all) { Rails.application.load_tasks if Rake::Task.tasks.empty? }

  around do |example|
    saved = ENV.fetch("REFETCH", nil)
    example.run
  ensure
    saved.nil? ? ENV.delete("REFETCH") : ENV["REFETCH"] = saved
  end

  def run_task
    task = Rake::Task["catalog:backfill_course_details"]
    task.reenable
    task.invoke
  end

  let(:term) { create(:term) }
  let!(:catalog_course) { create(:catalog_course, details_fetched_at: 1.day.ago) }

  before { create(:course, term: term) }

  it "queues a details sync for each term and keeps fresh courses fresh" do
    expect { run_task }.to output(/Enqueued Catalog::CourseDetailsSyncJob for 1 terms/).to_stdout
    expect(Catalog::CourseDetailsSyncJob).to have_been_enqueued.with(term.uid)
    expect(catalog_course.reload.details_fetched_at).to be_present
  end

  it "marks every course to fetch again with REFETCH" do
    ENV["REFETCH"] = "1"

    expect { run_task }.to output(/Marked 1 courses to fetch again/).to_stdout
    expect(catalog_course.reload.details_fetched_at).to be_nil
  end
end
