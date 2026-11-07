# frozen_string_literal: true

module Catalog
  # Waits out a Banner cooldown (Catalog::BannerThrottle) for a set time, not
  # for a set number of attempts.
  #
  # With retry_on, each cooldown used one attempt. Banner stops answering about
  # every 10 minutes, so a long run used its attempts in about 35 minutes and
  # landed in the failed list. Jobs that take turns under limits_concurrency
  # used their attempts faster, because a turn that starts during a cooldown
  # raises at once. "Retry all" on the admin page keeps the attempt count, so
  # a job with no attempts left failed again at once.
  #
  # Here the job tries again after each cooldown until the time window from its
  # first attempt ends. Then it reports the error as handled and stops, so the
  # failed list keeps only real errors.
  #
  # The time of the first attempt stays in the job data. "Retry" on one failed
  # job (SolidQueue::FailedExecution#retry) sets executions to 0, so the job
  # starts a new window. "Retry all" (FailedExecution.retry_all) keeps
  # executions, so a job whose window ended stops at its first cooldown. The
  # next nightly run does the work.
  #
  #   include Catalog::BannerCooldownRetry
  #   retry_banner_cooldown within: 4.hours
  module BannerCooldownRetry
    extend ActiveSupport::Concern

    WAIT = Catalog::BannerThrottle::COOLDOWN + 30.seconds

    # Up to this share of WAIT is added at random, as retry_on does. Without
    # it, every job that hit the same cooldown wakes in the same second and can
    # open the next cooldown together.
    JITTER = 0.15

    # The key in the serialized job. Each retry is a new Solid Queue job, so the
    # time of the first attempt travels with the job data.
    FIRST_ATTEMPT_KEY = "banner_first_attempt_at"

    included do
      class_attribute :banner_cooldown_window, instance_writer: false, default: 15.minutes
      attr_accessor :banner_first_attempt_at

      # executions is 1 on a new job, and on a job that "Retry" started again.
      before_perform do
        self.banner_first_attempt_at = Time.current if executions == 1 || banner_first_attempt_at.nil?
      end

      rescue_from Catalog::BannerThrottle::CooldownError do |error|
        if banner_cooldown_retry?
          retry_job(wait: WAIT + (WAIT * JITTER * rand), error: error)
        else
          Rails.logger.warn "[#{self.class.name}] Banner did not answer for #{banner_cooldown_window.inspect}. Stopped."
          Rails.error.report(error, handled: true,
                                    context: { job_class: self.class.name, job_id: job_id, executions: executions })
        end
      end
    end

    class_methods do
      def retry_banner_cooldown(within:)
        self.banner_cooldown_window = within
      end
    end

    def serialize
      super.merge(FIRST_ATTEMPT_KEY => banner_first_attempt_at&.iso8601(6))
    end

    def deserialize(job_data)
      super
      self.banner_first_attempt_at = job_data[FIRST_ATTEMPT_KEY]&.then { |time| Time.zone.parse(time) }
    end

    private

    # Try again only when the retry starts inside the window.
    def banner_cooldown_retry?
      Time.current + WAIT <= (banner_first_attempt_at || Time.current) + banner_cooldown_window
    end
  end
end
