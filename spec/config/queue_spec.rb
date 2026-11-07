# frozen_string_literal: true

require "rails_helper"

# Solid Queue reads config/queue.yml and the queue database only in
# production, so a wrong pool size shows up there as
# ActiveRecord::ConnectionTimeoutError in the worker, not in specs (#677).
RSpec.describe "config/queue.yml and config/database.yml" do
  def render(file, env)
    stub_const("ENV", ENV.to_h.merge(env))
    YAML.load(ERB.new(Rails.root.join("config", file).read).result, aliases: true).fetch("production")
  end

  [ {}, { "RAILS_MAX_THREADS" => "5", "JOB_THREADS" => "8" } ].each do |env|
    context "with #{env.presence || 'the default thread counts'}" do
      let(:databases) { render("database.yml", env) }
      let(:worker) { render("queue.yml", env).fetch("workers").sole }
      let(:web_threads) { Integer(env.fetch("RAILS_MAX_THREADS", 3)) }

      it "gives the queue pool the worker threads + 2 (Solid Queue README)" do
        expect(databases.dig("queue", "max_connections")).to be >= worker.fetch("threads") + 2
      end

      # In async mode the Puma threads and the worker threads share one pool.
      it "gives primary and cache one connection for each Puma and worker thread" do
        %w[primary cache].each do |name|
          expect(databases.dig(name, "max_connections")).to be >= web_threads + worker.fetch("threads")
        end
      end
    end
  end

  it "takes high before default, and default before low" do
    expect(render("queue.yml", {}).fetch("workers").sole.fetch("queues")).to eq(%w[high default low])
  end

  it "lists every queue that a job class names" do
    Rails.application.eager_load!
    queues = ApplicationJob.descendants.map(&:queue_name).uniq
    # deliver_later uses this queue; nil means the default queue.
    queues << (ActionMailer::Base.deliver_later_queue_name || "default").to_s

    expect(queues - %w[high default low]).to be_empty
  end
end
