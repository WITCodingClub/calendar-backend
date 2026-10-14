# frozen_string_literal: true

module Catalog
  # Every request to Banner (LeopardWeb, selfservice.wit.edu) goes through this
  # Faraday middleware. Catalog::LeopardWebClient adds it to each connection.
  #
  # On 2026-10-14 Banner answered HTTP 500 to every searchResults request after
  # about 40 requests in a minute, and worked again a few minutes later. So the
  # middleware does three things:
  #
  # 1. Pacing. A token bucket that the whole process shares: BURST requests at
  #    once, then RATE_PER_SECOND. One schedule in POST /api/process_courses
  #    sends about 18 requests, which fit in the burst. The nightly sync sends
  #    thousands, which the rate spreads out.
  # 2. Retries. 429 and 5xx answers and connection failures retry with
  #    exponential backoff and jitter, and Retry-After when Banner sends it. A
  #    web request has a small budget, so a student does not wait long. A job
  #    has a large one.
  # 3. Cooldown. After COOLDOWN_AFTER failures in a row, no request goes to
  #    Banner for COOLDOWN. Requests raise CooldownError at once, and jobs retry
  #    later.
  #
  # The state is in memory. Production runs one process (Puma with Solid Queue
  # inside it), so the memory is shared by the web requests and the jobs. With
  # more processes, move the bucket and the cooldown to a shared store.
  class BannerThrottle < Faraday::Middleware
    BURST = 20
    # Requests per second after the burst. The nightly sync for two terms sends
    # about 8,000 requests, which takes about 27 minutes at this rate.
    RATE_PER_SECOND = 5.0

    RETRY_STATUSES   = [ 429, 500, 502, 503, 504 ].freeze
    RETRY_EXCEPTIONS = [ Faraday::ConnectionFailed, Faraday::TimeoutError ].freeze

    BASE_DELAY = 0.5
    MAX_DELAY  = 30

    COOLDOWN_AFTER = 5
    COOLDOWN       = 3.minutes

    # How long one request may spend in retries, by caller.
    Budget = Data.define(:retries, :max_wait)
    BUDGETS = {
      request: Budget.new(retries: 2, max_wait: 3),
      job:     Budget.new(retries: 6, max_wait: 90)
    }.freeze

    # Banner answers these two only over POST, but neither changes data:
    # getEnrollmentInfo reads the seat counts, and term/search picks the term
    # for the session, which a second call picks again. So they retry like a
    # GET. Any other POST does not retry.
    RETRYABLE_POST_PATHS = %w[getEnrollmentInfo term/search].freeze

    # Raised while Banner cools down. It is a RequestError, so every caller
    # that handles a Banner failure handles it too.
    class CooldownError < LeopardWebClient::RequestError
      attr_reader :retry_after

      def initialize(retry_after)
        @retry_after = retry_after
        super("Banner is not answering. Try again in #{retry_after} seconds.", status: 503)
      end
    end

    @mutex = Mutex.new

    class << self
      def reset!
        @mutex.synchronize do
          @tokens        = BURST.to_f
          @refilled_at   = clock
          @failures      = 0
          @cooldown_until = nil
        end
      end

      # Takes one token, and waits when there is none. A negative balance
      # holds the place of each request that waits.
      def acquire
        wait = @mutex.synchronize do
          refill
          @tokens -= 1
          @tokens.negative? ? -@tokens / RATE_PER_SECOND : 0.0
        end
        pause(wait) if wait.positive?
        wait
      end

      def record_success
        @mutex.synchronize { @failures = 0 }
      end

      def record_failure
        @mutex.synchronize do
          @failures += 1
          next if @failures < COOLDOWN_AFTER

          @failures = 0
          @cooldown_until = clock + COOLDOWN.to_i
        end
      end

      # Seconds left in the cooldown, or nil.
      def cooldown_remaining
        @mutex.synchronize do
          left = @cooldown_until && (@cooldown_until - clock)
          left&.positive? ? left.ceil : nil
        end
      end

      # A job waits longer for Banner than a web request. ActiveJob puts the
      # job in ActiveSupport::ExecutionContext. Code that starts threads copies
      # the context into them (Concurrently, Courses::Processor), so a request
      # sent from a worker thread gets the budget of the job or the request
      # that started it. with_budget picks a budget by hand, for a rake task.
      def current_budget
        context = ActiveSupport::ExecutionContext.to_h
        context[:banner_budget] || (context[:job] ? :job : :request)
      end

      def with_budget(name, &)
        ActiveSupport::ExecutionContext.set(banner_budget: name, &)
      end

      # Specs replace this, so they do not wait.
      def pause(seconds)
        sleep(seconds)
      end

      def count(outcome)
        Yabeda.calendar.banner_requests_total.increment({ outcome: outcome })
      end

      private

      def refill
        now = clock
        @tokens = [ @tokens + ((now - @refilled_at) * RATE_PER_SECOND), BURST.to_f ].min
        @refilled_at = now
      end

      def clock
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end

    reset!

    def call(env)
      budget = BUDGETS.fetch(self.class.current_budget)
      request_body = env.body
      retries = 0
      waited  = 0.0

      loop do
        refuse_during_cooldown!
        self.class.acquire
        env.body = request_body

        begin
          response = @app.call(env)
        rescue *RETRY_EXCEPTIONS
          self.class.record_failure
          delay = backoff(retries)
          raise unless retry?(env, budget, retries, waited + delay)
        else
          unless RETRY_STATUSES.include?(response.status)
            self.class.record_success
            self.class.count(response.success? ? :ok : :failed)
            return response
          end

          self.class.record_failure
          delay = retry_after(response) || backoff(retries)
          return response unless retry?(env, budget, retries, waited + delay)
        end

        self.class.count(:retried)
        self.class.pause(delay)
        waited  += delay
        retries += 1
      end
    end

    private

    def refuse_during_cooldown!
      remaining = self.class.cooldown_remaining
      return unless remaining

      self.class.count(:cooldown)
      raise CooldownError, remaining
    end

    # Counts the final failure when the request will not retry.
    def retry?(env, budget, retries, total_wait)
      allowed = retryable_method?(env) &&
                retries < budget.retries &&
                total_wait <= budget.max_wait &&
                self.class.cooldown_remaining.nil?
      self.class.count(:failed) unless allowed
      allowed
    end

    def retryable_method?(env)
      return true if env.method == :get
      return false unless env.method == :post

      RETRYABLE_POST_PATHS.any? { |path| env.url.path.end_with?("/#{path}") }
    end

    def backoff(retries)
      delay = BASE_DELAY * (2**retries)
      [ delay + rand(0.0..(delay / 4)), MAX_DELAY ].min
    end

    # Retry-After in seconds. Banner has not been seen to send the date form.
    def retry_after(response)
      value = response.headers["Retry-After"].to_s
      return nil unless value.match?(/\A\d+\z/)

      [ value.to_i, MAX_DELAY ].min
    end
  end
end
