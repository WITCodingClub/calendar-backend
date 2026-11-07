# frozen_string_literal: true

# Jobs in the queue from before Faculties::RefreshRatingsJob still run. Remove
# this alias when `bin/rails jobs:unknown_class_names` on production lists no
# Faculties::FillMissingRmpIdsJob.
Faculties::FillMissingRmpIdsJob = Faculties::RefreshRatingsJob
