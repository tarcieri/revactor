#--
# Copyright (C)2007 Tony Arcieri
# You can redistribute this under the terms of the Ruby license
# See file LICENSE for details
#++

require File.dirname(__FILE__) + '/../lib/revactor/actor'

describe Actor do
  describe "creation" do
    it "lazily creates Actor.current" do
      Actor.current.should be_an_instance_of(Actor)
    end
    
    it "allows creation of new Actors with Actor.spawn" do
      root = Actor.current
      
      Actor.spawn do
        Actor.current.should be_an_instance_of(Actor)
        Actor.current.should_not eql(root)
      end
    end
    
    it "allows arguments to be passed when an Actor is created" do
      Actor.spawn(1, 2, 3) do |foo, bar, baz|
        [foo, bar, baz].should == [1, 2, 3]
      end
    end
  end
  
  describe "receive" do
    before :each do
      @actor_run = false
    end
    
    it "returns the value of the matching filter action" do
      actor = Actor.spawn do
        Actor.receive do |filter|
          filter.when(:foo) { |message| :bar }
        end.should == :bar
        
        # Make sure the spec actually ran the actor
        @actor_run = true
      end
      
      actor << :foo
      @actor_run.should be_true
    end
    
    it "filters messages with ===" do
      actor = Actor.spawn do
        results = []
        3.times do
          results << Actor.receive do |filter|
            filter.when(/third/) { |m| m }
            filter.when(/first/) { |m| m }
            filter.when(/second/) { |m| m }
          end
        end
        results.should == ['first message', 'second message', 'third message']
        @actor_run = true
      end
      
      ['first message', 'second message', 'third message'].each { |m| actor << m }
      @actor_run.should be_true
    end
        
    it "times out if a message isn't received after the specifed interval" do
      actor = Actor.spawn do
        Actor.receive do |filter|
          filter.when(:foo) { :wrong }
          filter.after(0.01) { :right }
        end.should == :right
        @actor_run = true
      end
      @actor_run.should be_true
    end
    
    it "matches any message with Object" do
      actor = Actor.spawn do
        result = []
        3.times do
          result << Actor.receive do |filter|
            filter.when(Object) { |m| m }
          end
        end
        
        result.should == [:foo, :bar, :baz]
        @actor_run = true
      end
      
      [:foo, :bar, :baz].each { |m| actor << m }
      @actor_run.should be_true
    end
  end
  
  describe "linking" do
    it "forwards exceptions to linked Actors" do
      Actor.spawn do
        actor = Actor.spawn_link do
          Actor.receive do |m|
            m.when(:die) { raise 'dying' }
          end
        end
    
        proc { actor << :die; Actor.sleep 0 }.should raise_error('dying')
      end
    end
    
    it "sends normal exit messages to linked Actors which are trapping exit" do
      Actor.spawn do
        Actor.current.trap_exit = true
        actor = Actor.spawn_link {}
        Actor.receive do |m|
          m.when(Case[:exit, actor, Object]) { |_, _, reason| reason }
        end.should == :normal
      end
    end
    
    it "delivers exceptions to linked Actors which are trapping exit" do
      error = RuntimeError.new("I fail!")
      
      Actor.spawn do
        Actor.current.trap_exit = true
        actor = Actor.spawn_link { raise error }
        Actor.receive do |m|
          m.when(Case[:exit, actor, Object]) { |_, _, reason| reason }
        end.should == error
      end
    end
  end
  
  it "detects dead actors" do
    actor = Actor.spawn do
      Actor.receive do |filter|
        filter.when(Object) {}
      end
    end
    
    actor.dead?.should be_false
    actor << :foobar
    actor.dead?.should be_true
  end
end