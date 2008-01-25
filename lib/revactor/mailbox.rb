#--
# Copyright (C)2007 Tony Arcieri
# You can redistribute this under the terms of the Ruby license
# See file LICENSE for details
#++

require File.dirname(__FILE__) + '/../revactor'

class Actor
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
      action = matched_index = nil
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
          unless (action = filter.match message)
            # The filter did not match an action for the current message
            # Keep track of which messages we've ran the filter across so it
            # isn't re-run against messages it already failed to match
            processed_upto += 1
            next
          end
        
          # We've found a matching action, so break out of the loop
          matched_index = processed_upto + index
          break
        end

        # If we've timed out, run the timeout action unless we found another
        action ||= @timeout_action if @timed_out

        # If no matching action is found, yield until we get another message
        reschedule unless action
      end

      if @timer
        @timer.detach if @timer.attached?
        @timer = nil
      end
    
      # If we encountered a timeout, call the action directly
      return action.call if @timed_out
    
      # Otherwise we matched a message, so process it with the action      
      return action.(@queue.delete_at matched_index)
    end
  
    #######
    private
    #######
  
    def reschedule
      actor = Actor.current
    
      if actor._scheduler.running? 
        Fiber.yield
      else
        raise "no event sources available" unless Rev::Loop.default.has_active_watchers?
        Fiber.new { actor._scheduler << actor }.resume
      end
    end
  
    # Timeout class, used to implement receive timeouts
    class Timer < Rev::TimerWatcher
      def initialize(timeout, actor)
        @actor = actor
        super(timeout)
      end

      def on_timer
        @actor.instance_eval { @_mailbox.timed_out = true }
        @actor._scheduler << @actor
      end
    end

    # Mailbox filterset.  Takes patterns or procs to match messages with
    # and returns the associated proc when a pattern matches.
    class Filter
      def initialize(mailbox)
        @mailbox = mailbox
        @ruleset = []
      end

      # Provide a pattern to match against with === and a block to call
      # when the pattern is matched.
      def when(pattern, &action)
        raise ArgumentError, "no block given" unless action
        @ruleset << [pattern, action]
      end

      # Provide a timeout (in seconds, can be a Float) to wait for matching
      # messages.  If the timeout elapses, the given block is called.
      def after(timeout, &action)
        raise ArgumentError, "timeout already specified" if @mailbox.timer
        raise ArgumentError, "must be zero or positive" if timeout < 0
      
        # Don't explicitly require an action to be specified for a timeout
        @mailbox.timeout_action = action || proc {}
      
        if timeout > 0
          @mailbox.timer = Timer.new(timeout, Actor.current).attach(Rev::Loop.default)
        else
          # No need to actually set a timer if the timeout is zero, 
          # just short-circuit waiting for one entirely...
          @timed_out = true
          Actor.current._scheduler << Actor.current
        end
      end

      # Match a message using the filter
      def match(message)
        _, action = @ruleset.find { |pattern, _| pattern === message }
        action
      end

      # Is the filterset empty?
      def empty?
        @ruleset.empty? and not @mailbox.timer
      end
    end
  end
end