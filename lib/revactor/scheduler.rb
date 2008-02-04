#--
# Copyright (C)2007 Tony Arcieri
# You can redistribute this under the terms of the Ruby license
# See file LICENSE for details
#++

require 'thread'
require File.dirname(__FILE__) + '/../revactor'

class Actor
  # The Actor Scheduler maintains a run queue of actors with outstanding
  # messages who have not yet processed their mailbox.  If all actors have
  # processed their mailboxes then the scheduler waits for any outstanding
  # Rev events.  If there are no active Rev watchers then the scheduler exits.
  class Scheduler
    attr_reader :mailbox
    
    def initialize
      @queue = []
      @running = false
      @mailbox = Mailbox.new
      
      @mailbox.attach Rev::Loop.default
    end

    # Schedule an Actor to be executed, and run the scheduler if it isn't
    # currently running
    def <<(actor)
      raise ArgumentError, "must be an Actor" unless actor.is_a? Actor
      
      @queue << actor unless @queue.last == actor
      
      unless @running
        # Reschedule the current Actor for execution
        @queue << Actor.current

        # Start the scheduler
        Fiber.new { run }.resume
      end
    end
    
    # Is the scheduler running?
    def running?; @running; end

    #########
    protected
    #########
      
    # Run the scheduler
    def run
      return if @running
    
      @running = true
      default_loop = Rev::Loop.default
    
      while true
        @queue.each do |actor|
          begin
            actor.fiber.resume
            handle_exit(actor) if actor.dead?
          rescue FiberError
            # Handle Actors whose Fibers died after being scheduled
            actor.instance_eval { @dead = true }
            handle_exit(actor)
          rescue => ex
            handle_exit(actor, ex)
          end
        end
      
        @queue.clear
        default_loop.run_once
      end
    end

    def handle_exit(actor, ex = nil)
      actor.instance_eval do
        # Mark Actor as dead
        @dead = true
        
        if @links.empty?
          Actor.scheduler.__send__(:log_exception, ex) if ex
        else
          # Notify all linked Actors of the exception
          @links.each do |link|
            link.notify_exited(actor, ex)
            Actor.scheduler << link
          end
        end
      end
    end
    
    def log_exception(ex)
      # FIXME this should go to a real logger
      STDERR.puts "#{ex.class}: #{[ex, *ex.backtrace].join("\n\t")}"
    end
    
    # The Scheduler Mailbox allows messages to be safely delivered across
    # threads.  If a thread is sleeping sending it a message will wake
    # it up.
    class Mailbox < Rev::IOWatcher
      def initialize
        @queue = []
        @lock = Mutex.new
        
        @reader, @writer = IO.pipe
        super(@reader)
      end
      
      def send(actor, message)
        @lock.synchronize { @queue << T[actor, message] }
        @writer.write "\0"
      end
            
      #########
      protected
      #########
      
      def on_readable
        @reader.read 1
        
        @lock.synchronize do
          @queue.each { |actor, message| actor << message }
          @queue.clear
        end
      end
    end
  end
end