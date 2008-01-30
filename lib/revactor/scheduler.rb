#--
# Copyright (C)2007 Tony Arcieri
# You can redistribute this under the terms of the Ruby license
# See file LICENSE for details
#++

require File.dirname(__FILE__) + '/../revactor'

class Actor
  # The Actor Scheduler maintains a run queue of actors with outstanding
  # messages who have not yet processed their mailbox.  If all actors have
  # processed their mailboxes then the scheduler waits for any outstanding
  # Rev events.  If there are no active Rev watchers then the scheduler exits.
  class Scheduler
    def initialize
      @queue = []
      @running = false
    end

    # Schedule an Actor to be executed, and run the scheduler if it isn't
    # currently running
    def <<(actor)
      raise ArgumentError, "must be an Actor" unless actor.is_a? Actor
      
      @queue << actor unless @queue.last == actor
      
      unless @running
        # Persist the fiber the scheduler runs in
        @fiber ||= Fiber.new do 
          loop { run; Fiber.yield }
        end
        
        # Resume the scheduler
        @fiber.resume
      end
    end
  
    # Run the scheduler
    def run
      return if @running
    
      @running = true
      default_loop = Rev::Loop.default
    
      until @queue.empty? and not default_loop.has_active_watchers?
        @queue.each do |actor|
          begin
            actor.fiber.resume
            handle_exception(actor, :normal) if actor.dead?
          rescue FiberError
            # Handle Actors that died after being scheduled
            handle_exception(actor, :normal)
          rescue => ex
            handle_exception(actor, ex)
          end
        end
      
        @queue.clear
        default_loop.run_once if default_loop.has_active_watchers?
      end
    
      @running = false
    end
  
    # Is the scheduler running?
    def running?
      @running
    end
    
    #########
    protected
    #########
    
    def handle_exception(actor, ex)
      actor.instance_eval do
        # Mark Actor as dead
        @dead = true
        
        if @links.empty?
          Actor.scheduler.__send__(:log_exception, ex) unless ex == :normal
        else
          # Notify all linked Actors of the exception
          @links.each do |link|
            link.__send__(:event, T[:exit, actor, ex])
            Actor.scheduler << link
          end
        end
      end
    end
    
    def log_exception(ex)
      # FIXME this should go to a real logger
      STDERR.puts "#{ex.class}: #{[ex, *ex.backtrace].join("\n\t")}"
    end
  end
end