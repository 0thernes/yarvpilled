# frozen_string_literal: true

require "fileutils"

module Yarvpilled
  # Renders the live simulation straight into ffmpeg (raw RGB24 on stdin ->
  # H.264 yuv420p MP4), saves PNG stills at dramatic real moments (a
  # GC.compact flash, a TracePoint rewrite, the final frame), derives a GIF
  # preview, and writes the run log with before/after disasm.
  class Video
    def initialize(opts)
      @opts = opts
      @out = opts[:out]
    end

    def run
      FileUtils.mkdir_p(@out)
      log = File.open(File.join(@out, "run_log.txt"), "w")
      log.puts "YARVPILLED run log | ruby #{RUBY_VERSION} | YJIT #{defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled?} | world=#{@opts[:world]} | seed=#{@opts[:seed]}"
      sim = Simulation.new(seed: @opts[:seed], world: @opts[:world], log: log)
      ren = Renderer.new(sim)
      fps = @opts[:fps]
      frames = @opts[:seconds] * fps
      mp4 = File.join(@out, "yarvpilled.mp4")
      cmd = ["ffmpeg", "-loglevel", "error", "-y", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", "#{Renderer::W}x#{Renderer::H}",
             "-r", fps.to_s, "-i", "-", "-c:v", "libx264", "-preset", "medium", "-crf", "19", "-pix_fmt", "yuv420p",
             "-movflags", "+faststart", mp4]
      stills = {}
      t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      IO.popen(cmd, "wb") do |ff|
        frames.times do |f|
          @opts[:tpf].times { sim.step! }
          canvas = ren.render
          ff.write(canvas.buf)
          grab_still(stills, sim, canvas, f, frames)
          if (f % fps).zero?
            $stderr.print format("\r  frame %4d/%d  t=%d pop=%d species=%d gen=%d rewrites=%d compacts=%d  ",
                                 f, frames, sim.tick, sim.alive_count, sim.live_species.size, sim.max_gen, sim.rewrites_total, sim.compacts)
          end
        end
      end
      raise "ffmpeg failed" unless $?.success?

      dt = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0
      stills.each { |name, png| File.binwrite(File.join(@out, "still_#{name}.png"), png) }
      summary = { frames: frames, seconds_wall: dt.round(1), ticks: sim.tick, max_gen: sim.max_gen, births: sim.births_total,
                  species_ever: sim.species.size, alive: sim.alive_count, rewrites: sim.rewrites_total, compacts: sim.compacts,
                  amnesias: sim.amnesias, mutations: sim.mutations_total, think_calls: sim.think_calls,
                  apex: sim.apex&.id, apex_len: sim.apex&.genome&.bytecode_len,
                  live_instructions: sim.live_species.sum { |s| s.genome.histogram.values.sum * s.alive },
                  distinct_opcodes: sim.live_species.flat_map { |s| s.genome.histogram.keys }.uniq.size }
      log.puts "\nSUMMARY #{summary.inspect}"
      log.close
      $stderr.puts "\n  wrote #{mp4} in #{dt.round(1)}s"
      gif
      File.write(File.join(@out, "summary.json"), JSON.pretty_generate(summary))
      sim.close
      summary
    end

    private

    def grab_still(stills, sim, canvas, f, frames)
      lc = sim.last_compact
      if !stills[:enlightenment] && lc && (6..7).cover?(sim.tick - lc[:tick].to_i) && f > frames / 4
        stills[:enlightenment] = canvas.to_png
      end
      rw = sim.rewrite_log.last
      if !stills[:rewrite] && rw && (6..7).cover?(sim.tick - rw[:fired_tick].to_i) && f > frames / 3
        stills[:rewrite] = canvas.to_png
      end
      stills[:world] = canvas.to_png if f == (frames * 0.62).to_i
      stills[:final] = canvas.to_png if f == frames - 1
    end

    def gif
      mp4 = File.join(@out, "yarvpilled.mp4")
      out = File.join(@out, "yarvpilled.gif")
      start = [@opts[:seconds] * 0.35, 0].max.round
      filter = "fps=12,scale=640:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=160:stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=4:diff_mode=rectangle"
      system("ffmpeg", "-loglevel", "error", "-y", "-ss", start.to_s, "-t", "14", "-i", mp4, "-vf", filter, out, exception: true)
    end
  end
end
