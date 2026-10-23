# frozen_string_literal: true

require "rails_helper"
require "rake"

RSpec.describe "finals:link_orphans" do
  include ActiveJob::TestHelper

  before(:all) do
    Rails.application.load_tasks if Rake::Task.tasks.empty?
  end

  around do |example|
    saved = ENV.fetch("CONFIRM", nil)
    example.run
  ensure
    saved.nil? ? ENV.delete("CONFIRM") : ENV["CONFIRM"] = saved
  end

  let(:term) { create(:term) }
  let(:user) { create(:user) }

  # An exam saved with no course while its course exists, as the old code
  # left it. update_column skips FinalExam's before_save link.
  def orphan_exam(exam_date:)
    course = create(:course, term: term)
    create(:enrollment, user: user, course: course)
    exam = create(:final_exam, term: term, crn: course.crn, exam_date: exam_date)
    exam.update_column(:course_id, nil) # rubocop:disable Rails/SkipsModelValidations
    [ exam, course ]
  end

  def run_task(confirm:)
    confirm ? ENV["CONFIRM"] = "1" : ENV.delete("CONFIRM")
    task = Rake::Task["finals:link_orphans"]
    task.reenable
    expect { task.invoke }.to output.to_stdout
  end

  it "changes nothing in a dry run" do
    exam, = orphan_exam(exam_date: 1.month.from_now.to_date)

    run_task(confirm: false)

    expect(exam.reload.course).to be_nil
    expect(enqueued_jobs).to be_empty
  end

  it "links an upcoming exam and re-syncs the calendars of the course's students" do
    exam, course = orphan_exam(exam_date: 1.month.from_now.to_date)
    unmatched = create(:final_exam, term: term, exam_date: 1.month.from_now.to_date)

    run_task(confirm: true)

    expect(exam.reload.course).to eq(course)
    expect(unmatched.reload.course).to be_nil
    expect(CourseCalendars::SyncJob).to have_been_enqueued.with(user, force: true)
  end

  it "leaves past exams alone" do
    exam, = orphan_exam(exam_date: 1.month.ago.to_date)

    run_task(confirm: true)

    expect(exam.reload.course).to be_nil
    expect(enqueued_jobs).to be_empty
  end
end
