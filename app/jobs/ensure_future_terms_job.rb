# frozen_string_literal: true

# The old name of Catalog::EnsureFutureTermsJob. Jobs that were in the queue
# before the rename still name this class. Remove this file when `bin/rails
# jobs:unknown_class_names` on production no longer lists EnsureFutureTermsJob.
EnsureFutureTermsJob = Catalog::EnsureFutureTermsJob
