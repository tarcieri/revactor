require 'thread'

class Thread
  def _fiber_scheduler
    @fiber_scheduler ||= Fiber::Scheduler.new
  end
end

class FiberError < StandardError; end

# Pseudo-Fibers built on top of Ruby 1.8's green threads
class Fiber
  def self.current
    Thread.current._fiber_scheduler.current_fiber
  end

  def self.yield
    raise FiberError, "can't yield from root fiber" if Thread.current._fiber_scheduler.current_fiber.root?
    Thread.current._fiber_scheduler.yield
  end
    
  def initialize(&routine)
    raise ArgumentError, "no block given" unless block_given?
    scheduler = Thread.current._fiber_scheduler
    
    @dead = false
    @root = false
    @thread = Thread.new do
      Thread.current.instance_variable_set(:@fiber_scheduler, scheduler)
      Thread.stop
      routine.call
      
      @dead = true
      Fiber.yield
    end
  end

  def resume
    raise FiberError, "dead fiber called" if dead?
    Thread.current._fiber_scheduler << self
    @thread.run
    Thread.stop
    nil
  end
  
  def dead?; @dead; end
  
  def root?; @root; end
  
  #######
  private
  #######
  
  def initialize_root
    @dead = false
    @root = true
    @thread = Thread.current
    
    self
  end

  class Scheduler
    def initialize
      @queue = [Fiber.allocate.send(:initialize_root)]
    end
    
    def <<(fiber)
      @queue << fiber
    end
    
    def current_fiber
      @queue.last
    end
  
    def yield
      @queue.pop
      @queue.last.resume
    end
  end
end
