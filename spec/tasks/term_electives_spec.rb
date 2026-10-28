# frozen_string_literal: true

require "rails_helper"
require "rake"

RSpec.describe "term_electives rake tasks" do
  before(:all) do
    Rails.application.load_tasks if Rake::Task.tasks.empty?
  end

  it "queues the import" do
    task = Rake::Task["term_electives:import"]
    task.reenable

    expect { task.invoke }.to have_enqueued_job(TermElectives::ImportJob)
      .and output("Queued the import of the term elective lists.\n").to_stdout
  end
end
