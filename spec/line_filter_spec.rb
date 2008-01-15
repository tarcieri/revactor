#--
# Copyright (C)2007 Tony Arcieri
# You can redistribute this under the terms of the Ruby license
# See file LICENSE for details
#++

require File.dirname(__FILE__) + '/../lib/revactor/filters/line'

describe Revactor::Filter::Line do
  before(:each) do
    @payload = "foo\nbar\r\nbaz\n"
    @filter = Revactor::Filter::Line.new
  end
  
  it "decodes lines from an input buffer" do
    @filter.decode(@payload).should == %w{foo bar baz}
  end
  
  it "encodes lines" do
    @filter.encode(*%w{foo bar baz}).should == "foo\nbar\nbaz\n"
  end
    
  it "reassembles fragmented lines" do
    msg1 = "foobar\r\n"
    msg2 = "baz\n"
    msg3 = "quux\r\n"
        
    chunks = []
    chunks[0] = msg1.slice(0, 1)
    chunks[1] = msg1.slice(1, msg1.size) << msg2.slice(0, 1)
    chunks[2] = msg2.slice(1, msg2.size - 1)
    chunks[3] = msg2.slice(msg2.size, 1) << msg3
        
    chunks.reduce([]) { |a, chunk| a + @filter.decode(chunk) }.should == %w{foobar baz quux}
  end
end
