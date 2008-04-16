#--
# Copyright (C)2007 Tony Arcieri
# You can redistribute this under the terms of the Ruby license
# See file LICENSE for details
#++

module Revactor
  module Filter
    # A filter for line based protocols which are framed using LF or CRLF 
    # encoding, such as IRC.  Both LF and CRLF are supported and no 
    # validation is done on bare LFs for CRLF encoding.  The output
    # is chomped and delivered without any newline.
    class Line
      MAX_LENGTH = 1048576 # Maximum length of a single line
      
      # Create a new Line filter.  Accepts the following options:
      #
      #   delimiter: A character to use as a delimiter.  Defaults to "\n"
      #              Character sequences are not supported.
      #
      #   maxlength: Maximum length of a line
      #
      def initialize(options = {})
        @input = ''
        @delimiter = options[:delimiter] || "\n"
        @size_limit = options[:maxlength] || MAX_LENGTH
      end
      
      # Callback for processing incoming lines
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
      
      # Encode lines using the current delimiter
      def encode(*data)
        data.inject("") { |str, d| str << d << @delimiter }
      end
    end
  end
end
  
