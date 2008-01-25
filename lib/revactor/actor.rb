#--
# Copyright (C)2007 Tony Arcieri
# You can redistribute this under the terms of the Ruby license
# See file LICENSE for details
#++

require File.dirname(__FILE__) + '/../revactor'
require 'fiber'

# Raised whenever any Actor-specific problems occur
class DeadActorError < StandardError; end

# Monkeypatch Fiber to include an accessor to its current Actor
class Fiber
  attr_reader :_actor
end

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
  attr_reader :_fiber
  attr_reader :_scheduler
  
  @@registered = {}

  class << self
    # Create a new Actor with the given block and arguments
    def spawn(*args, &block)
      raise ArgumentError, "no block given" unless block

      actor = Actor.new
      
      fiber = Fiber.new do 
        block.call(*args)
        actor.instance_eval { @_dead = true }
      end
      
      fiber.instance_eval { @_actor = actor }
      actor.instance_eval { 
        @_fiber = fiber
        @_scheduler = Actor.current._scheduler
      }
      
      Actor.current._scheduler << actor
      
      actor
    end
    
    # Obtain a handle to the current Actor
    def current
      return Fiber.current._actor if Fiber.current._actor
      
      actor = Actor.new
      
      Fiber.current.instance_eval { @_actor = actor }
      actor.instance_eval { 
        @_fiber = Fiber.current 
        @_scheduler = Scheduler.new
      }
      
      actor
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
  
  def initialize
    @_thread = Thread.current
    @_dead = false
    @_mailbox = Mailbox.new
    @_dictionary = {}
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
    return "can't send messages to actors across threads" unless @_thread == Thread.current
        
    # Erlang discards messages sent to dead actors, and if Erlang does it,
    # it must be the right thing to do, right?  Hooray for the Erlang 
    # cargo cult!  I think they do this because dealing with errors raised
    # from dead actors greatly overcomplicates overall error handling
    return message if dead?
    
    @_mailbox << message    
    @_scheduler << self
    
    message
  end

  alias_method :send, :<<
  
  #########
  protected
  #########
  
  attr_reader :_mailbox
end
