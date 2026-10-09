# frozen_string_literal: true

# The old name of Embeddings::GenerateJob. Jobs that were in the queue before
# the rename still name this class. Remove this file when `bin/rails
# jobs:unknown_class_names` on production no longer lists GenerateEmbeddingsJob.
GenerateEmbeddingsJob = Embeddings::GenerateJob
