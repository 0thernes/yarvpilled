# frozen_string_literal: true

require_relative "world" # loads Native if compiled
require_relative "raster_ruby"

module Yarvpilled
  # Glyph atlas generated once by tools/gen_font.rb (DejaVu Sans Mono via
  # ffmpeg drawtext) and committed as raw 8-bit coverage.
  class Font
    attr_reader :cw, :ch, :first, :count, :atlas

    def self.load(name)
      @cache ||= {}
      @cache[name] ||= new(File.binread(File.join(__dir__, "data", "font_#{name}.bin")))
    end

    def initialize(blob)
      @cw, @ch, @first, @count = blob.unpack("S<4")
      @atlas = blob.byteslice(8..).freeze
    end
  end

  # RGB24 framebuffer with drawing helpers backed by the C rasterizer (or
  # the pure-Ruby fallback).
  class Canvas
    R = Native::AVAILABLE ? Native::Raster : RasterRuby

    attr_reader :w, :h, :buf

    def initialize(w, h)
      @w = w
      @h = h
      @buf = ("\0".b * (w * h * 3))
    end

    def fill(c) = R.fill(@buf, @w, @h, *c)
    def rect(x, y, rw, rh, c, a = 255) = R.rect(@buf, @w, @h, x.to_i, y.to_i, rw.to_i, rh.to_i, *c, a.to_i)
    def glow(x, y, rad, c, a = 255) = R.glow(@buf, @w, @h, x.to_f, y.to_f, rad.to_f, *c, a.to_i)
    def disc(x, y, rad, c, a = 255) = R.disc(@buf, @w, @h, x.to_f, y.to_f, rad.to_f, *c, a.to_i)
    def ring(x, y, rad, th, c, a = 255) = R.ring(@buf, @w, @h, x.to_f, y.to_f, rad.to_f, th.to_f, *c, a.to_i)
    def arc(x, y, rad, th, a0, a1, c, a = 255) = R.arc(@buf, @w, @h, x.to_f, y.to_f, rad.to_f, th.to_f, a0.to_f, a1.to_f, *c, a.to_i)
    def ngon(x, y, rad, sides, rot, c, a = 255) = R.ngon(@buf, @w, @h, x.to_f, y.to_f, rad.to_f, sides.to_i, rot.to_f, *c, a.to_i)
    def line(x0, y0, x1, y1, c, a = 255, add: false) = R.line(@buf, @w, @h, x0.to_f, y0.to_f, x1.to_f, y1.to_f, *c, a.to_i, add)
    def scale(x, y, rw, rh, num) = R.scale(@buf, @w, @h, x, y, rw, rh, num)
    def scanlines(strength) = R.scanlines(@buf, @w, @h, strength)
    def blit_add(src, x, y) = R.blit_add(@buf, @w, @h, src.buf, src.w, src.h, x, y)

    def heat(field, cols, rows, cell, ox, oy, palette)
      R.heat(@buf, @w, @h, field, cols, rows, cell, ox, oy, palette)
    end

    def text(str, x, y, c, a = 255, font: :small)
      f = Font.load(font)
      R.text(@buf, @w, @h, f.atlas, f.cw, f.ch, f.first, f.count, str.to_s.encode("ASCII", undef: :replace, invalid: :replace, replace: "?"), x.to_i, y.to_i, *c, a.to_i)
    end

    def text_width(str, font: :small) = str.to_s.size * Font.load(font).cw

    # Neon panel: dark glass, glowing border, corner brackets, title tab.
    def panel(x, y, pw, ph, title, c)
      rect(x, y, pw, ph, [6, 8, 18], 210)
      rect(x, y, pw, 1, c, 150)
      rect(x, y + ph - 1, pw, 1, c, 70)
      rect(x, y, 1, ph, c, 90)
      rect(x + pw - 1, y, 1, ph, c, 90)
      [[x, y, 1, 1], [x + pw - 12, y, -1, 1], [x, y + ph - 2, 1, -1], [x + pw - 12, y + ph - 2, -1, -1]].each do |bx, by, _sx, _sy|
        rect(bx, by, 12, 2, c, 255)
      end
      rect(x, y, 2, 12, c, 255)
      rect(x + pw - 2, y, 2, 12, c, 255)
      rect(x, y + ph - 12, 2, 12, c, 255)
      rect(x + pw - 2, y + ph - 12, 2, 12, c, 255)
      return unless title

      tw = text_width(title, font: :bold) + 16
      rect(x + 14, y - 8, tw, 16, [8, 10, 24], 255)
      rect(x + 14, y - 8, tw, 16, c, 40)
      text(title, x + 22, y - 8, c, 255, font: :bold)
    end

    # P6 is trivial; PNG via the pure-Ruby encoder.
    def to_png = Png.encode(@w, @h, @buf)
  end

  # Minimal PNG encoder: stdlib Zlib for DEFLATE + CRC32, filter type 0.
  module Png
    require "zlib"
    module_function

    def encode(w, h, rgb)
      raw = +"".b
      stride = w * 3
      h.times { |y| raw << "\0" << rgb.byteslice(y * stride, stride) }
      ihdr = [w, h, 8, 2, 0, 0, 0].pack("NNCCCCC")
      "\x89PNG\r\n\x1a\n".b + chunk("IHDR", ihdr) + chunk("IDAT", Zlib::Deflate.deflate(raw, 6)) + chunk("IEND", "")
    end

    def chunk(type, data)
      [data.bytesize].pack("N") + type.b + data.b + [Zlib.crc32(type + data)].pack("N")
    end
  end
end
