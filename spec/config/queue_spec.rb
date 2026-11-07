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

  let(:worker_queues) { render("queue.yml", {}).fetch("workers").sole.fetch("queues") }

  it "takes high before default, and default before low" do
    expect(worker_queues.first(3)).to eq(%w[high default low])
  end

  # A job on a queue that no worker reads stays ready forever. Gem jobs count
  # too: console1984 schedules its cleanup on its own queue.
  it "lists every queue that a job class names" do
    Rails.application.eager_load!
    # Leave out classes that other specs made with stub_const. They stay in
    # descendants after the constant is gone. Also leave out the job proxy of
    # mission_control-jobs: it stands in for a stored job on the admin jobs
    # page and is never enqueued. It loads only when the app eager loads, as
    # it does when CI is set, so this spec failed only in CI.
    jobs = ActiveJob::Base.descendants.select { |job| job.name&.safe_constantize.equal?(job) }
    jobs -= [ ActiveJob::JobProxy ] if defined?(ActiveJob::JobProxy)
    queues = jobs.to_h do |job|
      # A Proc queue name needs an instance. The mail job's Proc reads the
      # mailer class from the first argument.
      args = job <= ActionMailer::MailDeliveryJob ? [ ApplicationMailer.name ] : []
      [ job.name, job.queue_name.is_a?(Proc) ? job.new(*args).queue_name : job.queue_name ]
    rescue StandardError => e
      [ job.name, "#{e.class}: #{e.message}" ]
    end

    # SolidQueue::RecurringJob runs only for a recurring task with no queue.
    # The recurring spec below covers that case.
    readable = worker_queues + [ SolidQueue::RecurringJob.queue_name ]
    expect(queues.reject { |_job, queue| readable.include?(queue) }).to be_empty
  end

  it "gives every recurring task a queue that a worker reads" do
    tasks = YAML.load_file(Rails.root.join("config/recurring.yml")).fetch("production")

    expect(tasks.values.map { |task| task["queue"] }.uniq - worker_queues).to be_empty
  end
end
