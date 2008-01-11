#--
# Copyright (C)2007 Tony Arcieri
# You can redistribute this under the terms of the Ruby license
# See file LICENSE for details
#++

module Revactor
  module Filters
    class Line
      MAX_LENGTH = 1048576 # Maximum length of a single line
      
      def initialize(options = {})
        @input = ''
        @delimiter = options[:delimiter] || "\n"
        @size_limit = options[:maxlength] || MAX_LENGTH
      end
      
      def decode(data)
        lines = data.split @delimiter, -1
        
        if @size_limit and @input.size + lines.first.size > @size_limit
          raise 'input buffer full' 
        end
        
        @input << lines.shift
        return [] if lines.empty?
        
        lines.unshift @input
        @input = lines.pop
        
        lines.map(&:chomp)
      end
      
      def encode(*data)
        data.reduce("") { |str, d| str << d << @delimiter }
      end
    end
  end
end
  