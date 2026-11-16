# frozen_string_literal: true

require "rails_helper"
require "rake"

RSpec.describe "courses:refresh_faculty" do
  before(:all) do
    Rails.application.load_tasks if Rake::Task.tasks.empty?
  end

  let(:term) { create(:term) }

  def run_task(*args)
    task = Rake::Task["courses:refresh_faculty"]
    task.reenable
    task.invoke(*args)
  end

  it "syncs every section of the term through Catalog::SectionSync" do
    courses = create_list(:course, 2, term: term)
    allow(Catalog::SectionSync).to receive(:call_many).and_return(synced: 1, errors: 0)

    expect { run_task(term.uid.to_s) }.to output(/1 sections changed, 0 failed/).to_stdout
    expect(Catalog::SectionSync).to have_received(:call_many).with(courses.map(&:id).sort)
  end

  it "stops when the term does not exist" do
    expect { run_task("209910") }.to raise_error(SystemExit).and output(/No terms found/).to_stderr
  end
end
