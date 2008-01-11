#--
# Copyright (C)2007 Tony Arcieri
# You can redistribute this under the terms of the Ruby license
# See file LICENSE for details
#++

require 'rubygems'
require 'rev'

# This is mostly in hopes of a bright future with Rubinius
# The recommended container for all datagrams sent between
# Actors is a Tuple, defined below, and with a 'T' shortcut:
unless defined? Tuple
  # A Tuple class.  Will (eventually) be a subset of Array
  # with fixed size and faster performance, at least that's
  # the hope with Rubinius...
  class Tuple < Array; end
end

# Shortcut Tuple as T
T = Tuple unless defined? T

require File.dirname(__FILE__) + '/revactor/actor'
require File.dirname(__FILE__) + '/revactor/server'
require File.dirname(__FILE__) + '/revactor/tcp'
require File.dirname(__FILE__) + '/revactor/behaviors/server'
