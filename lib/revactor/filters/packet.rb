#--
# Copyright (C)2007 Tony Arcieri
# You can redistribute this under the terms of the Ruby license
# See file LICENSE for details
#++

# Use buffering from Rev
require 'rubygems'
require 'rev'

module Revactor
  module Filter
    class Packet
      def initialize(size = 2)
        unless size == 2 or size == 4
          raise ArgumentError, 'only 2 or 4 byte prefixes are supported' 
        end
        
        @prefix_size = size
        @data_size = 0
        
        @mode = :prefix
        @buffer = Rev::Buffer.new
      end

      # Callback for processing incoming frames
      def decode(data)
        received = []
        @buffer << data
      
        begin  
          if @mode == :prefix
            break if @buffer.size < @prefix_size
            prefix = @buffer.read @prefix_size
            @data_size = prefix.unpack(@prefix_size == 2 ? 'n' : 'N').first
            @mode = :data
          end
        
          break if @buffer.size < @data_size
          received << @buffer.read(@data_size)
          @mode = :prefix
        end until @buffer.empty?
        
        received
      end

      # Send a packet with a specified size prefix
      def encode(*data)
        data.reduce('') do |s, d|
          raise ArgumentError, 'packet too long for prefix length' if d.size >= 256 ** @prefix_size
          s << [d.size].pack(@prefix_size == 2 ? 'n' : 'N') << d
        end
      end
    end
  end
end