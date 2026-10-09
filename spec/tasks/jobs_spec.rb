# frozen_string_literal: true

require "rails_helper"
require "rake"

RSpec.describe "jobs rake tasks" do
  before(:all) do
    Rails.application.load_tasks if Rake::Task.tasks.empty?
  end

  def run_task(name)
    task = Rake::Task[name]
    task.reenable
    task.invoke
  end

  # Solid Queue rows are built by hand, as CLAUDE.md asks for records that a gem owns.
  def enqueue(class_name, finished_at: nil)
    SolidQueue::Job.create!(
      queue_name: "default", class_name: class_name, arguments: {},
      active_job_id: SecureRandom.uuid, finished_at: finished_at
    )
  end

  describe "jobs:unknown_class_names" do
    it "lists unfinished jobs whose class is no longer a job class, by name" do
      2.times { enqueue("OldNameSyncJob") }
      enqueue("GoogleCalendarSyncJob")
      enqueue("FinishedOldNameJob", finished_at: Time.current)

      expect { run_task("jobs:unknown_class_names") }.to output("OldNameSyncJob: 2\n").to_stdout
    end

    it "says so when every unfinished job uses a current class name" do
      enqueue("GoogleCalendarSyncJob")

      expect { run_task("jobs:unknown_class_names") }.to output(/Every unfinished job uses a current class name/).to_stdout
    end
  end
end
