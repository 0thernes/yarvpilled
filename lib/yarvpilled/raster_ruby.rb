# frozen_string_literal: true

module Yarvpilled
  # Pure-Ruby fallback for ext/yarvpilled_native/raster.c with the same
  # module-function signatures. Correct but slow; used only when the C
  # extension is not compiled.
  module RasterRuby
    module_function

    def px_blend(s, w, h, x, y, r, g, b, a)
      return if x.negative? || y.negative? || x >= w || y >= h || a <= 0

      a = 255 if a > 255
      o = (y * w + x) * 3
      q0 = s.getbyte(o)
      q1 = s.getbyte(o + 1)
      q2 = s.getbyte(o + 2)
      s.setbyte(o, q0 + ((r - q0) * a / 255.0).truncate)
      s.setbyte(o + 1, q1 + ((g - q1) * a / 255.0).truncate)
      s.setbyte(o + 2, q2 + ((b - q2) * a / 255.0).truncate)
    end

    def px_add(s, w, h, x, y, r, g, b, a)
      return if x.negative? || y.negative? || x >= w || y >= h || a <= 0

      o = (y * w + x) * 3
      s.setbyte(o, [s.getbyte(o) + r * a / 255, 255].min)
      s.setbyte(o + 1, [s.getbyte(o + 1) + g * a / 255, 255].min)
      s.setbyte(o + 2, [s.getbyte(o + 2) + b * a / 255, 255].min)
    end

    def fill(s, w, h, r, g, b)
      s.replace([r, g, b].pack("C3") * (w * h))
    end

    def rect(s, w, h, x0, y0, rw, rh, r, g, b, a)
      (y0...(y0 + rh)).each { |y| (x0...(x0 + rw)).each { |x| px_blend(s, w, h, x, y, r, g, b, a) } }
      s
    end

    def glow(s, w, h, cx, cy, rad, r, g, b, a)
      return s if rad <= 0

      ((cy - rad).to_i..(cy + rad).to_i).each do |y|
        ((cx - rad).to_i..(cx + rad).to_i).each do |x|
          dx = x + 0.5 - cx
          dy = y + 0.5 - cy
          d = Math.sqrt(dx * dx + dy * dy) / rad
          next if d >= 1.0

          f = (1.0 - d) * (1.0 - d)
          px_add(s, w, h, x, y, r, g, b, (a * f).to_i)
        end
      end
      s
    end

    def disc(s, w, h, cx, cy, rad, r, g, b, a)
      ((cy - rad - 1).to_i..(cy + rad + 1).to_i).each do |y|
        ((cx - rad - 1).to_i..(cx + rad + 1).to_i).each do |x|
          dx = x + 0.5 - cx
          dy = y + 0.5 - cy
          cov = rad + 0.5 - Math.sqrt(dx * dx + dy * dy)
          next if cov <= 0

          px_blend(s, w, h, x, y, r, g, b, (a * [cov, 1].min).to_i)
        end
      end
      s
    end

    def ring(s, w, h, cx, cy, rad, th, r, g, b, a) = arc(s, w, h, cx, cy, rad, th, -Math::PI, Math::PI, r, g, b, a)

    def arc(s, w, h, cx, cy, rad, th, a0, a1, r, g, b, a)
      ((cy - rad - th - 1).to_i..(cy + rad + th + 1).to_i).each do |y|
        ((cx - rad - th - 1).to_i..(cx + rad + th + 1).to_i).each do |x|
          dx = x + 0.5 - cx
          dy = y + 0.5 - cy
          cov = th / 2.0 + 0.5 - (Math.sqrt(dx * dx + dy * dy) - rad).abs
          next if cov <= 0

          ang = Math.atan2(dy, dx)
          ang += 2 * Math::PI if ang < a0
          next if ang < a0 || ang > a1

          px_blend(s, w, h, x, y, r, g, b, (a * [cov, 1].min).to_i)
        end
      end
      s
    end

    def ngon(s, w, h, cx, cy, rad, sides, rot, r, g, b, a)
      n = sides.clamp(3, 12)
      pts = Array.new(n) { |k| [cx + Math.cos(rot + 2 * Math::PI * k / n) * rad, cy + Math.sin(rot + 2 * Math::PI * k / n) * rad] }
      ((cy - rad - 1).to_i..(cy + rad + 1).to_i).each do |y|
        ((cx - rad - 1).to_i..(cx + rad + 1).to_i).each do |x|
          hits = 4.times.count do |si|
            sx = x + 0.25 + 0.5 * (si & 1)
            sy = y + 0.25 + 0.5 * (si >> 1)
            n.times.all? do |k|
              x1, y1 = pts[k]
              x2, y2 = pts[(k + 1) % n]
              (x2 - x1) * (sy - y1) - (y2 - y1) * (sx - x1) >= 0
            end
          end
          px_blend(s, w, h, x, y, r, g, b, a * hits / 4) if hits.positive?
        end
      end
      s
    end

    def line(s, w, h, x0, y0, x1, y1, r, g, b, a, additive)
      dx = x1 - x0
      dy = y1 - y0
      steep = dy.abs > dx.abs
      steps = [(steep ? dy.abs : dx.abs).ceil, 1].max
      plot = additive ? method(:px_add) : method(:px_blend)
      (0..steps).each do |st|
        t = st.to_f / steps
        x = x0 + dx * t
        y = y0 + dy * t
        if steep
          xi = x.floor
          f = x - xi
          plot.call(s, w, h, xi, y.to_i, r, g, b, (a * (1 - f)).to_i)
          plot.call(s, w, h, xi + 1, y.to_i, r, g, b, (a * f).to_i)
        else
          yi = y.floor
          f = y - yi
          plot.call(s, w, h, x.to_i, yi, r, g, b, (a * (1 - f)).to_i)
          plot.call(s, w, h, x.to_i, yi + 1, r, g, b, (a * f).to_i)
        end
      end
      s
    end

    def scale(s, w, h, x0, y0, rw, rh, num)
      ([y0, 0].max...[y0 + rh, h].min).each do |y|
        ([x0, 0].max...[x0 + rw, w].min).each do |x|
          o = (y * w + x) * 3
          3.times { |k| s.setbyte(o + k, (s.getbyte(o + k) * num) >> 8) }
        end
      end
      s
    end

    def text(s, w, h, atlas, cw, ch, first, count, str, x, y, r, g, b, a)
      stride = cw * count
      str.each_byte do |byte|
        c = byte - first
        if c.positive? && c < count
          ch.times do |gy|
            cw.times do |gx|
              cov = atlas.getbyte(gy * stride + c * cw + gx)
              px_blend(s, w, h, x + gx, y + gy, r, g, b, cov * a / 255) if cov.positive?
            end
          end
        end
        x += cw
      end
      x
    end

    def heat(s, w, h, field, cols, rows, cell, ox, oy, pal)
      (rows * cell).times do |y|
        fy = (y + 0.5) / cell - 0.5
        y0 = fy.floor
        ty = fy - y0
        ya = (y0 + rows) % rows
        yb = (y0 + 1) % rows
        (cols * cell).times do |x|
          fx = (x + 0.5) / cell - 0.5
          x0 = fx.floor
          tx = fx - x0
          xa = (x0 + cols) % cols
          xb = (x0 + 1) % cols
          v = (field.getbyte(ya * cols + xa) * (1 - tx) + field.getbyte(ya * cols + xb) * tx) * (1 - ty) +
              (field.getbyte(yb * cols + xa) * (1 - tx) + field.getbyte(yb * cols + xb) * tx) * ty
          vi = [v.to_i, 255].min
          px_add(s, w, h, ox + x, oy + y, pal.getbyte(vi * 3), pal.getbyte(vi * 3 + 1), pal.getbyte(vi * 3 + 2), 255)
        end
      end
      s
    end

    def blit_add(dst, dw, dh, src, sw, sh, dx, dy)
      sh.times do |y|
        sw.times do |x|
          o = (y * sw + x) * 3
          px_add(dst, dw, dh, x + dx, y + dy, src.getbyte(o), src.getbyte(o + 1), src.getbyte(o + 2), 255)
        end
      end
      dst
    end

    def scanlines(s, w, h, strength)
      cx = w / 2.0
      cy = h / 2.0
      maxd = Math.hypot(cx, cy)
      h.times do |y|
        line = y.odd? ? 256 - strength : 256
        w.times do |x|
          d = Math.hypot(x - cx, y - cy) / maxd
          k = (line * (256 - 110 * d * d * d).to_i) >> 8
          o = (y * w + x) * 3
          3.times { |c| s.setbyte(o + c, (s.getbyte(o + c) * k) >> 8) }
        end
      end
      s
    end
  end
end
