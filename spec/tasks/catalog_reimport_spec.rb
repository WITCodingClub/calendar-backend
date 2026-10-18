# frozen_string_literal: true

require "rails_helper"
require "rake"

RSpec.describe "catalog:reimport_all_terms" do
  include ActiveJob::TestHelper

  before(:all) { Rails.application.load_tasks if Rake::Task.tasks.empty? }

  around do |example|
    keys = %w[FROM TO DRY_RUN]
    saved = keys.to_h { |key| [ key, ENV.fetch(key, nil) ] }
    example.run
  ensure
    saved.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  def run_task
    task = Rake::Task["catalog:reimport_all_terms"]
    task.reenable
    task.invoke
  end

  it "queues one coordinator job with the bounds" do
    ENV["FROM"] = "202600"
    ENV["TO"]   = "202799"

    expect { run_task }.to output(/one term at a time/).to_stdout
    expect(enqueued_jobs.map { |job| job["job_class"] }).to eq([ "Catalog::ReimportAllTermsJob" ])
    expect(Catalog::ReimportAllTermsJob).to have_been_enqueued.with(from: "202600", to: "202799")
  end

  it "prints the plan and queues nothing on a dry run" do
    ENV["DRY_RUN"] = "1"
    result = Catalog::ReimportPlan::Result.new(term_uids: [ 202720, 202710 ], missing_in_database: [ 202730 ],
                                               missing_in_banner: [ 201420 ])
    allow(Catalog::ReimportPlan).to receive(:new).with(from: nil, to: nil)
                                                 .and_return(instance_double(Catalog::ReimportPlan, call: result))

    expect { run_task }.to output(/Would import 2 terms, newest first:\n  202720\n  202710\n.*not in the database.*202730.*no longer lists.*201420/m).to_stdout
    expect(enqueued_jobs).to be_empty
  end

  %w[0 false].each do |value|
    it "queues the job when DRY_RUN is #{value}" do
      ENV["DRY_RUN"] = value

      expect { run_task }.to output(/one term at a time/).to_stdout
      expect(Catalog::ReimportAllTermsJob).to have_been_enqueued
    end
  end
end
