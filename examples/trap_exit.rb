# An example of trapping exit messages
#
# Here we create a new Actor which raises an unhandled exception
# whenever it receives the :die message.
#
# The parent Actor is linked to this one, and is set to trap exits
# When the child raises the unhandled exception, the exit message
# is delivered back to the parent.

require 'rubygems'
require 'revactor'

actor = Actor.spawn_link do
  Actor.receive do |filter|
    filter.when(:die) { raise "Aieeee!" }
  end
end

Actor.current.trap_exit = true

actor << :die
p Actor.receive { |filter| filter.when(Object) { |msg| msg } }
