#--
# Copyright (C)2007 Tony Arcieri
# You can redistribute this under the terms of the Ruby license
# See file LICENSE for details
#++

require File.dirname(__FILE__) + '/../revactor'

# The Actor Scheduler maintains a run queue of actors with outstanding
# messages who have not yet processed their mailbox.  If all actors have
# processed their mailboxes then the scheduler waits for any outstanding
# Rev events.  If there are no active Rev watchers then the scheduler exits.
class Actor::Scheduler
  @@queue = []
  @@running = false

  class << self
    # Schedule an Actor to be executed, and run the scheduler if it isn't
    # currently running
    def <<(actor)
      raise ArgumentError, "must be an Actor" unless actor.is_a? Actor

      @@queue << actor unless @@queue.last == actor
      run unless @@running
    end
    
    # Run the scheduler
    def run
      return if @@running
      @@running = true
      default_loop = Rev::Loop.default
      
      until @@queue.empty? and default_loop.watchers.empty?
        @@queue.each do |actor|
          begin
            actor.resume
          rescue FiberError # Fiber may have died since being scheduled 
          end
        end
        
        @@queue.clear
        
        default_loop.run_once unless default_loop.watchers.empty?
      end
      
      @@running = false
    end
  end
end