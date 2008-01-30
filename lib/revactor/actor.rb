#--
# Copyright (C)2007 Tony Arcieri
# You can redistribute this under the terms of the Ruby license
# See file LICENSE for details
#++

require File.dirname(__FILE__) + '/../revactor'
require 'thread'
require 'fiber'

# Monkeypatch Thread to include a method for obtaining the current Scheduler
class Thread
  def _revactor_scheduler
    @_revactor_scheduler ||= Actor::Scheduler.new
  end
end

# Monkeypatch Fiber to include a method for obtaining the current Actor
class Fiber
  def _actor
    @_actor ||= Actor.new
  end
end

# Error raised when attempting to link to dead Actors
class DeadActorError < StandardError; end

# Actors are lightweight concurrency primitives which communiucate via message
# passing.  Each actor has a mailbox which it scans for matching messages.
# An actor sleeps until it receives a message, at which time it scans messages
# against its filter set and then executes appropriate callbacks.
#
# The Actor class is definined in the global scope in hopes of being generally
# useful for Ruby 1.9 users while also attempting to be as compatible as
# possible with the Omnibus and Rubinius Actor implementations.  In this way it 
# should be possible to run programs written using Revactor to on top of other
# Actor implementations.
#
class Actor
  attr_reader :fiber
  attr_reader :scheduler
  attr_reader :mailbox
  
  @@registered = {}

  class << self
    # Create a new Actor with the given block and arguments
    def spawn(*args, &block)
      raise ArgumentError, "no block given" unless block
      
      actor = _spawn(*args, &block)
      scheduler << actor
      actor
    end
    
    # Spawn an Actor and immediately link it to the current one
    def spawn_link(*args, &block)
      raise ArgumentError, "no block given" unless block
      
      actor = _spawn(*args, &block)
      current.link actor
      scheduler << actor
      actor
    end
    
    # Link the current Actor to another one
    def link(actor)
      current.link actor
    end
    
    # Unlink the current Actor from another one
    def unlink(actor)
      current.unlink actor
    end
    
    # Obtain a handle to the current Actor
    def current
      Fiber.current._actor
    end
    
    # Obtain a handle to the current Scheduler
    def scheduler
      Thread.current._revactor_scheduler
    end
    
    # Reschedule the current actor for execution later
    def reschedule
      if scheduler.running? 
        Fiber.yield
      else
        scheduler << current
      end
      
      current.__send__(:process_events)
    end
    
    # Sleep for the specified number of seconds
    def sleep(seconds)
      receive { |filter| filter.after(seconds) }
    end
    
    # Wait for messages matching a given filter.  The filter object is yielded
    # to be block passed to receive.  You can then invoke the when argument
    # which takes a parameter and a block.  Messages are compared (using ===)
    # against the parameter.  The Case gem includes several tools for matching
    # messages using ===
    #
    # The first filter to match a message in the mailbox is executed.  If no
    # filters match then the actor sleeps.
    def receive(&filter)
      current.mailbox.receive(&filter)
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
    
    #########
    protected
    #########
    
    def _spawn(*args, &block)
      fiber = Fiber.new do
        block.call(*args)
        current.instance_eval { @dead = true }
      end
      
      actor = Actor.new(fiber)
      fiber.instance_eval { @_actor = actor }
    end
  end
  
  def initialize(fiber = Fiber.current)
    raise ArgumentError, "use Actor.spawn to create actors" if block_given?
    
    @fiber = fiber
    @scheduler = Actor.scheduler
    @thread = Thread.current
    @mailbox = Mailbox.new
    @links = []
    @events = []
    @trap_exit = false
    @dead = false
    @dictionary = {}
  end
  
  alias_method :inspect, :to_s
  
  # Look up value in the actor's dictionary
  def [](key)
    @dictionary[key]
  end
  
  # Store a value in the actor's dictionary
  def []=(key, value)
    @dictionary[key] = value
  end
  
  # Delete a value from the actor's dictionary
  def delete(key, &block)
    @dictionary.delete(key, &block)
  end
  
  # Is the current actor dead?
  def dead?; @dead; end
  
  # Send a message to an actor
  def <<(message)
    return "can't send messages to actors across threads" unless @thread == Thread.current
        
    # Erlang discards messages sent to dead actors, and if Erlang does it,
    # it must be the right thing to do, right?  Hooray for the Erlang 
    # cargo cult!  I think they do this because dealing with errors raised
    # from dead actors greatly overcomplicates overall error handling
    return message if dead?
    
    @mailbox << message    
    @scheduler << self
    
    message
  end

  alias_method :send, :<<
  
  # Establish a bidirectional link to the given Actor and notify it of any
  # system events which occur in this Actor (namely exits due to exceptions)
  def link(actor)
    actor.notify_link self
    self.notify_link actor
  end
  
  # Unestablish a link with the given actor
  def unlink(actor)
    actor.notify_unlink self
    self.notify_unlink actor
  end
  
  # Notify this actor that it's now linked to the given one
  def notify_link(actor)
    raise ArgumentError, "can only link to Actors" unless actor.is_a? Actor
    
    # Don't allow linking to dead actors
    raise DeadActorError, "actor is dead" if actor.dead?
    
    # Ignore circular links
    return true if actor == self
    
    # Ignore duplicate links
    return true if @links.include? actor
    
    @links << actor
    true
  end
  
  # Notify this actor that it's now unlinked from the given one
  def notify_unlink(actor)
    @links.delete(actor)
    true
  end
  
  # Notify this actor that one of the Actors it's linked to has exited
  def notify_exited(actor, reason)
    @events << T[:exit, actor, reason]
  end
  
  # Actors trapping exit do not die when an error occurs in an Actor they
  # are linked to.  Instead the exit message is sent to their regular
  # mailbox in the form [:exit, actor, reason].  This allows certain
  # Actors to supervise sets of others and restart them in the event
  # of an error.
  def trap_exit=(value)
    raise ArgumentError, "must be true or false" unless value == true or value == false
    @trap_exit = value
  end
  
  # Is the Actor trapping exit?
  def trap_exit?
    @trap_exit
  end
  
  #########
  protected
  #########
  
  # Process the Actor's system event queue
  def process_events
    @events.each do |event|
      type, *operands = event
      case type
      when :exit
        actor, ex = operands
        notify_unlink actor
        
        if @trap_exit
          self << event
        elsif ex
          raise ex
        end
      end
    end
    
    @events.clear
  end
end