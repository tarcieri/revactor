#!/usr/bin/env ruby

require File.dirname(__FILE__) + '/../lib/revactor/mongrel'

ADDR = '127.0.0.1'
PORT = 8080

server = Mongrel::HttpServer.new(ADDR, PORT)
server.register '/', Mongrel::DirHandler.new(".")

puts "Running on #{ADDR}:#{PORT}"
server.run
