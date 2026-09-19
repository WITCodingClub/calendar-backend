# frozen_string_literal: true

# Gives the Flipper UI a label for each actor on a feature page.
#
# Flipper matches a user only on its flipper_id, "User;<id>". The UI passes the
# raw gate values here, so a lookup must remove the "User;" prefix first. A gate
# entered as an email or a public id never matches a user, so its label says so
# and names the value to enter instead. FlipperUserActorAdapter converts new
# gates, so only gates saved before it, or values that match no user, get that
# label.
module FlipperActorNames
  USER_PREFIX = "User;"

  # Returns { gate value => label } for the values that have a label.
  def self.call(actor_ids)
    ids = actor_ids.filter_map { |value| value.delete_prefix(USER_PREFIX) if value.start_with?(USER_PREFIX) }
    names = User.where(id: ids).to_h { |user| [ user.flipper_id, user.email ] }

    actor_ids.each do |value|
      next if value.start_with?(USER_PREFIX)

      user = user_for(value)
      names[value] = "NOT MATCHED: enter #{user ? "#{user.flipper_id} for #{user.email}" : "User;<id>"}"
    end

    names
  end

  # Returns the user that an email or a public id names, or nil.
  def self.user_for(value)
    value.include?("@") ? User.find_by(email: value) : User.find_by_public_id(value)
  end
end
