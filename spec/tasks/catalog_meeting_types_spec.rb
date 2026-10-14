# frozen_string_literal: true

require "rails_helper"
require "rake"

RSpec.describe "catalog:fix_lab_meeting_types" do
  before(:all) do
    Rails.application.load_tasks if Rake::Task.tasks.empty?
  end

  def run_task
    task = Rake::Task["catalog:fix_lab_meeting_types"]
    task.reenable
    expect { task.invoke }.to output(/Marked 2 meeting times as labs/).to_stdout
  end

  it "marks the lecture meetings of lab sections as labs and leaves lectures alone" do
    lab        = create(:course, schedule_type: :laboratory)
    rotating   = create(:course, schedule_type: :rotating_lab)
    lecture    = create(:course, schedule_type: :lecture)
    lab_mt     = create(:course_meeting_time, course: lab, meeting_schedule_type: :lecture)
    rot_mt     = create(:course_meeting_time, course: rotating, meeting_schedule_type: :lecture)
    lecture_mt = create(:course_meeting_time, course: lecture, meeting_schedule_type: :lecture)

    run_task

    expect(lab_mt.reload).to be_laboratory
    expect(rot_mt.reload).to be_laboratory
    expect(lecture_mt.reload).to be_lecture
  end
end
