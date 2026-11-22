# frozen_string_literal: true

require_relative "test_helper"
require "zlib"

class TestRenderAndIO < Minitest::Test
  def test_png_encoder_round_trips
    c = Yarvpilled::Canvas.new(4, 3)
    c.rect(1, 1, 2, 1, [255, 0, 128])
    png = c.to_png
    assert png.start_with?("\x89PNG\r\n\x1a\n".b)
    w, h = png.byteslice(16, 8).unpack("NN")
    assert_equal [4, 3], [w, h]
    idat = png.byteslice(33 + 8, png.byteslice(33, 4).unpack1("N"))
    raw = Zlib::Inflate.inflate(idat)
    assert_equal [255, 0, 128], raw.byteslice(1 + 13 + 3, 3).bytes
  end

  def test_c_raster_matches_ruby_raster
    skip "C extension not compiled" unless Yarvpilled::Native::AVAILABLE
    f = Yarvpilled::Font.load(:small)
    bufs = [Yarvpilled::Native::Raster, Yarvpilled::RasterRuby].map do |r|
      b = "\0".b * (64 * 48 * 3)
      r.fill(b, 64, 48, 10, 20, 30)
      r.rect(b, 64, 48, 3, 4, 20, 10, 200, 100, 50, 128)
      r.disc(b, 64, 48, 30.5, 20.2, 7.3, 0, 255, 200, 230)
      r.glow(b, 64, 48, 40.0, 30.0, 9.0, 255, 40, 200, 180)
      r.ngon(b, 64, 48, 12.0, 30.0, 8.0, 5, 0.4, 255, 255, 0, 200)
      r.text(b, 64, 48, f.atlas, f.cw, f.ch, f.first, f.count, "YARV", 2, 34, 255, 255, 255, 255)
      b
    end
    assert_equal bufs[0], bufs[1]
  end

  def test_render_frame_and_telemetry
    sim = Yarvpilled::Simulation.new(seed: 11)
    20.times { sim.step! }
    canvas = Yarvpilled::Renderer.new(sim).render
    assert_equal 1280 * 720 * 3, canvas.buf.bytesize
    assert_operator canvas.buf.bytes.uniq.size, :>, 50
    data = JSON.parse(Yarvpilled::Telemetry.to_json(sim, full: true))
    assert_equal sim.alive_count, data["creatures"].size
    assert_includes data["apex"]["disasm"].first, "disasm"
    assert data["food"]["b64"]
  ensure
    sim&.close
  end
end
