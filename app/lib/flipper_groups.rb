# frozen_string_literal: true

# Resolves the group gates that a flag can be enabled for.
#
# Flipper gives a group block a Flipper::Types::Actor wrapper, not the object
# that was passed to Flipper.enabled?. The wrapper sends an unknown method on to
# the object it holds, so actor.admin_access? works, but is_a? is a real method
# on the wrapper, so actor.is_a?(User) is always false. A group block that starts
# with that check never matches, and the flag reads as disabled for every user in
# the group. Unwrap the actor first, then check the class.
module FlipperGroups
  # Each group name, and the test that a user must pass to be in that group.
  MATCHERS = {
    users:        ->(_user) { true },
    admins:       ->(user) { user.admin_access? },
    super_admins: ->(user) { user.super_admin? || user.owner? },
    owners:       ->(user) { user.owner? }
  }.freeze

  ALL = MATCHERS.keys.freeze

  # Returns true if the actor is a user in the named group.
  def self.match?(name, actor)
    user = user_for(actor)
    return false if user.nil?

    MATCHERS.fetch(name.to_sym).call(user)
  end

  # Returns the user that a Flipper actor holds, or nil for any other actor.
  def self.user_for(actor)
    thing = actor.is_a?(Flipper::Types::Actor) ? actor.actor : actor
    thing if thing.is_a?(User)
  end

  # Registers every group with Flipper. Call this once, at boot: Flipper raises
  # Flipper::Registry::DuplicateKey on a second registration of the same name.
  def self.register_all
    ALL.each do |name|
      Flipper.register(name) { |actor, _context| match?(name, actor) }
    end
  end
end
