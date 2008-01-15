#--
# Copyright (C)2007 Tony Arcieri
# You can redistribute this under the terms of the Ruby license
# See file LICENSE for details
#++

require File.dirname(__FILE__) + '/../revactor'
require 'fiber'

class ActorError < StandardError; end

# Actors are lightweight concurrency primitives which communiucate via message
# passing.  Each actor has a mailbox which it scans for matching messages.
# An actor sleeps until it receives a message, at which time it scans messages
# against its filter set and then executes appropriate callbacks.
#
# The Actor class is definined in the global scope in hopes of being generally
# useful for Ruby 1.9 users while also attempting to be as compatible as
# possible with the Rubinius Actor implementation.  In this way it should
# be possible to run programs written using Rev on top of Rubinius and hopefully
# get some better performance.
#
# Rev Actor implements some features that Rubinius does not, however, such as
# receive timeouts, receive filter-by-proc, arguments passed to spawn, and an
# actor dictionary (used for networking functionality).  Hopefully these 
# additional features will not get in the way of Rubinius / Rev compatibility.
#
class Actor < Fiber
  include Enumerable
    
  # Actor::ANY_MESSAGE can be used in a filter match any message
  ANY_MESSAGE = Object unless defined? Actor::ANY_MESSAGE
  @@registered = {}

  class << self
    include Enumerable

    # Create a new Actor with the given block and arguments
    def new(*args, &block)
      raise ArgumentError, "no block given" unless block
      actor = super() do 
        block.call(*args)
        Actor.current.instance_eval { @_dead = true }
      end

      # For whatever reason #initialize is never called in subclasses of Fiber
      actor.instance_eval do 
        @_dead = false
        @_mailbox = Mailbox.new
        @_dictionary = {}
      end

      Scheduler << actor
      actor
    end
    
    alias_method :spawn, :new
    
    # This will be defined differently in the future, but now the two are the same
    alias_method :start, :new
    
    # Obtain a handle to the current Actor
    def current
      actor = super
      raise ActorError, "current fiber is not an actor" unless actor.is_a? Actor
      
      actor 
    end
    
    # Wait for messages matching a given filter.  The filter object is yielded
    # to be block passed to receive.  You can then invoke the when argument
    # which takes a parameter and a block.  Messages are compared (using ===)
    # against the parameter, or if the parameter is a proc it is called with
    # a message and matches if the proc returns true.
    #
    # The first filter to match a message in the mailbox is executed.  If no
    # filters match then the actor sleeps.
    def receive(&filter)
      unless current.is_a?(Actor)
        raise ActorError, "receive must be called in the context of an Actor"
      end

      current.__send__(:_mailbox).receive(&filter)
    end

    # Look up an actor in the global dictionary
    def [](key)
      @@registered[key]
    end

    # Register this actor in the global dictionary
    def []=(key, actor)
      unless actor.is_a?(Actor)
        raise ArgumentError, "only actors may be registered"
      end

      @@registered[key] = actor
    end

    # Delete an actor from the global dictionary
    def delete(key, &block)
      @@registered.delete(key, &block)
    end

    # Iterate over the actors in the global dictionary
    def each(&block)
      @@registered.each(&block)
    end
  end
  
  # Look up value in the actor's dictionary
  def [](key)
    @_dictionary[key]
  end
  
  # Store a value in the actor's dictionary
  def []=(key, value)
    @_dictionary[key] = value
  end
  
  # Delete a value from the actor's dictionary
  def delete(key, &block)
    @_dictionary.delete(key, &block)
  end
  
  # Iterate over values in the actor's dictionary
  def each(&block)
    @_dictionary.each(&block)
  end
  
  # Is the current actor dead?
  def dead?; @_dead; end
  
  # Send a message to an actor
  def <<(message)
    # Erlang discards messages sent to dead actors, and if Erlang does it,
    # it must be the right thing to do, right?  Hooray for the Erlang 
    # cargo cult!  I think they do this because dealing with errors raised
    # from dead actors complicates overall error handling too much to be worth it.
    return message if dead?
    
    @_mailbox << message
    Scheduler << self
    message
  end

  alias_method :send, :<<
  
  #########
  protected
  #########
  
  attr_reader :_mailbox
  
  # Actor scheduler class, maintains a run queue of actors with outstanding
  # messages who have not yet processed their mailbox.  If all actors have
  # processed their mailboxes then the scheduler waits for any outstanding
  # Rev events.  If there are no active Rev watchers then the scheduler exits.
  class Scheduler
    @@queue = []
    @@running = false

    class << self
      def <<(actor)
        @@queue << actor
        run unless @@running
      end
      
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

  # Actor mailbox.  For purposes of efficiency the mailbox also handles 
  # suspending and resuming an actor when no messages match its filter set.
  class Mailbox
    attr_accessor :timer
    attr_accessor :timed_out
    attr_accessor :timeout_action

    def initialize
      @timer = nil
      @queue = []
    end

    # Add a message to the mailbox queue
    def <<(message)
      @queue << message
    end

    # Attempt to receive a message
    def receive
      raise ArgumentError, "no filter block given" unless block_given?

      # Clear mailbox processing variables
      action = matched_index = matched_message = nil
      processed_upto = 0
      
      # Clear timeout variables
      @timed_out = false
      @timeout_action = nil
      
      # Build the filter
      filter = Filter.new(self)
      yield filter
      raise ArgumentError, "empty filter" if filter.empty?

      # Process incoming messages
      while action.nil?
        @queue[processed_upto..@queue.size].each_with_index do |message, index|
          processed_upto += 1
          next unless (action = filter.match message)
          
          # We've found a matching action, so break out of the loop
          matched_index = index
          matched_message = message

          break
        end

        # If we've timed out, run the timeout action unless another has been found
        action ||= @timeout_action if @timed_out

        # If we didn't find a matching action, yield until we get another message
        Actor.yield unless action
      end

      if @timer
        @timer.detach if @timer.attached?
        @timer = nil
      end
      
      # If we encountered a timeout, call the action directly
      return action.call if @timed_out
      
      # Otherwise we matched a message, so process it with the action
      @queue.delete_at matched_index
      return action.(matched_message)
    end

    # Timeout class, used to implement receive timeouts
    class Timer < Rev::TimerWatcher
      def initialize(timeout, actor)
        @actor = actor
        super(timeout)
      end

      def on_timer
        @actor.instance_eval { @_mailbox.timed_out = true }
        Scheduler << @actor
      end
    end
 
    # Mailbox filterset.  Takes patterns or procs to match messages with
    # and returns the associated proc when a pattern matches.
    class Filter
      def initialize(mailbox)
        @mailbox = mailbox
        @ruleset = []
      end

      def when(pattern, &action)
        raise ArgumentError, "no block given" unless action
        @ruleset << [pattern, action]
      end

      def after(timeout, &action)
        raise ArgumentError, "timeout already specified" if @mailbox.timer
        raise ArgumentError, "must be zero or positive" if timeout < 0
        @mailbox.timeout_action = action
        
        if timeout > 0
          @mailbox.timer = Timer.new(timeout, Actor.current).attach(Rev::Loop.default)
        else
          # No need to actually set a timer if the timeout is zero, 
          # just short-circuit waiting for one entirely...
          @timed_out = true
          Scheduler << self
        end
      end

      def match(message)
        _, action = @ruleset.find do |pattern, _|
          if pattern.is_a? Proc
            pattern.(message)
          else
            pattern === message
          end
        end

        action
      end

      def empty?
        @ruleset.empty?
      end
    end
  end
end
