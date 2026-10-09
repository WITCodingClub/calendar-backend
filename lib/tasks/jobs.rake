# frozen_string_literal: true

namespace :jobs do
  # After a job class is renamed, its old name stays in the queue until the
  # last job with that name finishes. An alias file at the old path keeps those
  # jobs running. This task lists the old names that unfinished jobs still use,
  # so we know when the aliases can go. An alias defines a constant, but it is
  # not a subclass of its own, so ApplicationJob.descendants lists only the new
  # names, and the task needs no list of old names.
  desc "List unfinished Solid Queue jobs whose class name is not a current job class"
  task unknown_class_names: :environment do
    Rails.application.eager_load!
    known  = ApplicationJob.descendants.map(&:name)
    counts = SolidQueue::Job.where(finished_at: nil).where.not(class_name: known).group(:class_name).count

    if counts.empty?
      puts "Every unfinished job uses a current class name."
    else
      counts.sort.each { |name, count| puts "#{name}: #{count}" }
    end
  end
end
