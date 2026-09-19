# frozen_string_literal: true

# Lets an admin add a user to an actor gate by email or public id.
#
# Flipper matches a user only on "User;<id>", but the Flipper UI saves whatever
# the admin types. This adapter replaces an email or a public id with the
# flipper_id of that user before the gate is saved. A value that matches no user
# raises UnknownActor, because a gate that matches nobody does nothing.
#
# Disable removes the typed value and the user's flipper_id, and never raises,
# so the remove button also clears a gate that was saved before this adapter.
class FlipperUserActorAdapter < Flipper::Adapters::Wrapper
  class UnknownActor < ArgumentError; end

  def enable(feature, gate, thing)
    return super unless gate.key == :actors

    user = user_for(thing.value)
    raise UnknownActor, "#{thing.value.inspect} matches no user. Enter an email, a usr_ id, or User;<id>." unless user

    super(feature, gate, Flipper::Types::Actor.new(user))
  end

  def disable(feature, gate, thing)
    if gate.key == :actors && !thing.value.start_with?(FlipperActorNames::USER_PREFIX)
      user = user_for(thing.value)
      super(feature, gate, Flipper::Types::Actor.new(user)) if user
    end

    super
  end

  private

  def user_for(value)
    if value.start_with?(FlipperActorNames::USER_PREFIX)
      User.find_by(id: value.delete_prefix(FlipperActorNames::USER_PREFIX))
    else
      FlipperActorNames.user_for(value)
    end
  end

  # Sends the admin back to the add-actor form with the UnknownActor message,
  # which the form shows, instead of an error page.
  class UnknownActorRedirect
    def initialize(app)
      @app = app
    end

    def call(env)
      @app.call(env)
    rescue UnknownActor => e
      request = Rack::Request.new(env)
      [ 302, { "location" => "#{request.path}?#{Rack::Utils.build_query("error" => e.message)}" }, [] ]
    end
  end
end
