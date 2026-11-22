#!/usr/bin/env ruby
# frozen_string_literal: true

# Live browser mode: one Simulation thread, a stdlib TCPServer, and a
# Server-Sent Events stream of real VM telemetry rendered on a <canvas>.
#
#   ruby --yjit server.rb [--port=4567] [--bind=127.0.0.1] [--tps=20]
#   (binds to localhost by default; pass --bind=0.0.0.0 to expose it on your LAN)
#   open http://localhost:4567/          (SSE at /events, one-shot JSON at /state.json)

$LOAD_PATH.unshift File.join(__dir__, "lib")
Warning[:experimental] = false
require "socket"
require "optparse"
require "fileutils"
require "yarvpilled"

opts = { port: Integer(ENV.fetch("PORT", 4567)), bind: ENV.fetch("BIND", "127.0.0.1"), tps: 20, seed: 11,
         world: Yarvpilled::Native::AVAILABLE ? :native : :ruby }
OptionParser.new do |o|
  o.on("--port=N", Integer) { opts[:port] = _1 }
  o.on("--bind=ADDR") { opts[:bind] = _1 }
  o.on("--tps=N", Integer, "simulation ticks per second") { opts[:tps] = _1 }
  o.on("--seed=N", Integer) { opts[:seed] = _1 }
  o.on("--world=KIND", %w[native c asm rust ruby]) { opts[:world] = _1.to_sym }
end.parse!

module Yarvpilled
  class LiveServer
    INDEX = File.join(__dir__, "public", "index.html")

    def initialize(opts)
      @opts = opts
      @clients = []
      @lock = Mutex.new
      @latest = nil
      @latest_full = nil
      FileUtils.mkdir_p(File.join(__dir__, "out"))
      @log = File.open(File.join(__dir__, "out", "server_log.txt"), "a")
      @sim = Simulation.new(seed: opts[:seed], world: opts[:world], log: @log)
    end

    def start
      sim_thread
      server = TCPServer.new(@opts[:bind], @opts[:port])
      $stdout.puts "YARVPILLED live on http://#{@opts[:bind]}:#{@opts[:port]}/  (SSE /events)"
      $stdout.flush
      loop do
        sock = server.accept
        Thread.new(sock) { |s| handle(s) }
      end
    end

    private

    def sim_thread
      Thread.new do
        period = 1.0 / @opts[:tps]
        loop do
          t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          @sim.step!
          payload = Telemetry.to_json(@sim)
          full = Telemetry.to_json(@sim, full: true) if @latest_full.nil? || (@sim.tick % 10).zero?
          @lock.synchronize do
            @latest_full = full if full
            @latest = payload
            @clients.each { |q| q << payload if q.size < 30 }
          end
          dt = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0
          sleep(period - dt) if dt < period
        rescue StandardError => e
          warn "sim error: #{e.class}: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
          sleep 0.5
        end
      end
    end

    def handle(sock)
      request = sock.gets.to_s
      while (line = sock.gets) && line != "\r\n"; end
      path = request.split[1].to_s.split("?").first.to_s
      case path
      when "/", "/index.html" then respond(sock, 200, "text/html; charset=utf-8", File.read(INDEX))
      when "/state.json" then respond(sock, 200, "application/json", @lock.synchronize { @latest_full }.to_s)
      when "/healthz" then respond(sock, 200, "text/plain", "ok tick=#{@sim.tick}\n")
      when %r{\A/events} then stream(sock)
      else respond(sock, 404, "text/plain", "not found\n")
      end
    rescue IOError, Errno::EPIPE, Errno::ECONNRESET
      nil
    ensure
      sock.close unless sock.closed?
    end

    def respond(sock, code, type, body)
      sock.write("HTTP/1.1 #{code} #{code == 200 ? 'OK' : 'Not Found'}\r\nContent-Type: #{type}\r\n" \
                 "Content-Length: #{body.bytesize}\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n")
      sock.write(body)
    end

    def stream(sock)
      sock.write("HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nCache-Control: no-cache\r\n" \
                 "Connection: keep-alive\r\nAccess-Control-Allow-Origin: *\r\n\r\n")
      q = Queue.new
      first = @lock.synchronize do
        @clients << q
        @latest_full
      end
      sock.write("event: frame\ndata: #{first}\n\n")
      loop { sock.write("event: frame\ndata: #{q.pop}\n\n") }
    ensure
      @lock.synchronize { @clients.delete(q) }
    end
  end
end

Yarvpilled::LiveServer.new(opts).start
