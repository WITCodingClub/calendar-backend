# frozen_string_literal: true

require "rails_helper"
require "rake"

RSpec.describe "term_electives rake tasks" do
  before(:all) do
    Rails.application.load_tasks if Rake::Task.tasks.empty?
  end

  it "runs the import and prints the counts" do
    result = TermElectives::Importer::Result.new(imported: 2, unchanged: 1, skipped: 0, failed: 0, removed: 0)
    allow(TermElectives::Importer).to receive(:new).and_return(instance_double(TermElectives::Importer, call: result))

    task = Rake::Task["term_electives:import"]
    task.reenable

    expect { task.invoke }.to output("imported: 2, unchanged: 1, skipped: 0, failed: 0, removed: 0\n").to_stdout
  end
end
