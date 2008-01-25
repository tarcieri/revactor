#--
# Copyright (C)2007 Tony Arcieri
# You can redistribute this under the terms of the Ruby license
# See file LICENSE for details
#++

require File.dirname(__FILE__) + '/../lib/revactor'

describe Actor::Delegator do
  before :each do
    @obj = mock(:obj)
    @delegator = Actor::Delegator.new(@obj)
  end
  
  it "delegates calls to the given object" do
    @obj.should_receive(:foo).with(1)
    @obj.should_receive(:bar).with(2)
    @obj.should_receive(:baz).with(3)
    
    @delegator.foo(1)
    @delegator.bar(2)
    @delegator.baz(3)
  end
  
  it "returns the value from calls to the delegate object" do
    input_value = 42
    output_value = 420
    
    @obj.should_receive(:spiffy).with(input_value).and_return(input_value * 10)
    @delegator.spiffy(input_value).should == output_value
  end
  
  it "captures exceptions in the delegate and raises them for the caller" do
    ex = "crash!"
    
    @obj.should_receive(:crashy_method).and_raise(ex)
    proc { @delegator.crashy_method }.should raise_error(ex)
  end
  
  it "passes blocks along to the delegate" do
    prc = proc { "yay" }
    
    @obj.should_receive(:blocky).with(&prc)
    @delegator.blocky(&prc)
  end
end