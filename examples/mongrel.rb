#!/usr/bin/env ruby

$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)
require 'revactor'
require 'revactor/mongrel'

ADDR = '127.0.0.1'
PORT = 8080

server = Mongrel::HttpServer.new(ADDR, PORT)
server.register '/', Mongrel::DirHandler.new(".")

puts "Running on #{ADDR}:#{PORT}"
server.start
