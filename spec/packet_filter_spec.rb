#--
# Copyright (C)2007 Tony Arcieri
# You can redistribute this under the terms of the Ruby license
# See file LICENSE for details
#++

require File.dirname(__FILE__) + '/../lib/revactor/filters/packet'

describe Revactor::Filter::Packet do
  before(:each) do
    @payload = "A test string"
  end
  
  it "decodes frames with 2-byte prefixes" do
    filter = Revactor::Filter::Packet.new(2)
    filter.decode([@payload.length].pack('n') << @payload).should == [@payload]
  end
  
  it "encodes frames with 2-byte prefixes" do
    filter = Revactor::Filter::Packet.new(2)
    filter.encode(@payload).should == [@payload.length].pack('n') << @payload
  end
    
  it "decodes frames with 4-byte prefixes" do
    @filter = Revactor::Filter::Packet.new(4)    
    @filter.decode([@payload.length].pack('N') << @payload).should == [@payload]
  end
  
  it "encodes frames with 4-byte prefixes" do
    @filter = Revactor::Filter::Packet.new(4)    
    @filter.encode(@payload).should == [@payload.length].pack('N') << @payload
  end
  
  it "reassembles fragmented frames" do
    filter = Revactor::Filter::Packet.new(2)
    
    msg1 = 'foobar'
    msg2 = 'baz'
    msg3 = 'quux'
    
    packet1 = [msg1.length].pack('n') << msg1
    packet2 = [msg2.length].pack('n') << msg2
    packet3 = [msg3.length].pack('n') << msg3
        
    chunks = []
    chunks[0] = packet1.slice(0, 1)
    chunks[1] = packet1.slice(1, packet1.size) << packet2.slice(0, 1)
    chunks[2] = packet2.slice(1, packet2.size - 1)
    chunks[3] = packet2.slice(packet2.size, 1) << packet3
    
    chunks.inject([]) { |a, chunk| a + filter.decode(chunk) }.should == [msg1, msg2, msg3]
  end

  it "raises an exception for overlength frames" do
    filter = Revactor::Filter::Packet.new(2)
    payload = 'X' * 65537
    proc { filter.encode payload }.should raise_error(ArgumentError)
  end
end
