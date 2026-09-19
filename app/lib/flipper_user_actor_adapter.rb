# frozen_string_literal: true

# Lets an admin add a user to an actor gate by email or public id.
#
# Flipper matches a user only on "User;<id>", but the Flipper UI saves whatever
# the admin types. This adapter replaces an email or a public id with the
# flipper_id of that user before the gate is saved. A value that matches no user
# is saved as typed, so the UI still labels it NOT MATCHED.
#
# Disable removes the typed value and the user's flipper_id, so the remove
# button also clears a gate that was saved before this adapter.
class FlipperUserActorAdapter < Flipper::Adapters::Wrapper
  def enable(feature, gate, thing)
    super(feature, gate, user_thing(gate, thing) || thing)
  end

  def disable(feature, gate, thing)
    user = user_thing(gate, thing)
    super(feature, gate, user) if user
    super(feature, gate, thing)
  end

  private

  def user_thing(gate, thing)
    return unless gate.key == :actors
    return if thing.value.start_with?(FlipperActorNames::USER_PREFIX)

    user = FlipperActorNames.user_for(thing.value)
    Flipper::Types::Actor.new(user) if user
  end
end
