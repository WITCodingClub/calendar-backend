# frozen_string_literal: true

# The state of each one-time catch-up run for one student, for
# GET and PUT /api/user/backfills. Every name in UserBackfill::NAMES is in the
# body, with completed false until the extension marks it done.
class UserBackfillsSerializer
  def initialize(user)
    @user = user
  end

  def as_json(*)
    done = @user.user_backfills.pluck(:name, :completed_at).to_h

    UserBackfill::NAMES.values.index_with do |name|
      { completed: done.key?(name), completed_at: done[name]&.iso8601 }
    end
  end
end
