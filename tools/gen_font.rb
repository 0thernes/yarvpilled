# frozen_string_literal: true
# Generates the anti-aliased glyph atlases in lib/yarvpilled/data/ by asking
# ffmpeg's drawtext (libfreetype) to rasterize DejaVu Sans Mono, one glyph per
# cell. Run once; the output is committed so the demo needs no fonts at runtime.
#
#   ruby tools/gen_font.rb
require "tmpdir"

FONT = ENV.fetch("FONT", "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf")
FIRST = 32
LAST = 126
SIZES = { "small" => [10, 6, 12], "large" => [17, 10, 20], "bold" => [13, 8, 16] }.freeze
BOLD_FONT = FONT.sub("DejaVuSansMono.ttf", "DejaVuSansMono-Bold.ttf")

out_dir = File.expand_path("../lib/yarvpilled/data", __dir__)
Dir.mktmpdir do |tmp|
  SIZES.each do |name, (pt, cw, ch)|
    font = name == "bold" || name == "large" ? BOLD_FONT : FONT
    n = LAST - FIRST + 1
    filters = (FIRST..LAST).map.with_index do |code, i|
      path = File.join(tmp, "g#{code}.txt")
      File.binwrite(path, "\u2588" + code.chr) # full block pins the baseline; cropped below
      "drawtext=fontfile=#{font}:textfile=#{path}:fontsize=#{pt}:expansion=none:fontcolor=white:x=#{i * cw * 2}:y=#{(ch - pt) / 2 - 1}"
    end
    raw = File.join(tmp, "#{name}.gray")
    cmd = ["ffmpeg", "-loglevel", "error", "-y", "-f", "lavfi", "-i", "color=c=black:s=#{n * cw * 2}x#{ch}:d=1",
           "-vf", filters.join(","), "-frames:v", "1", "-pix_fmt", "gray", "-f", "rawvideo", raw]
    system(*cmd, exception: true)
    wide = File.binread(raw)
    stride = n * cw * 2
    data = +""
    ch.times do |row|
      n.times { |i| data << wide.byteslice(row * stride + i * cw * 2 + cw, cw) }
    end
    # The block's anti-aliased right edge can bleed into column 0 of each cell;
    # measure it on the space glyph (index 0) and subtract it everywhere.
    row_len = n * cw
    ch.times do |row|
      bleed = data.getbyte(row * row_len)
      next if bleed.zero?
      n.times do |i|
        off = row * row_len + i * cw
        data.setbyte(off, [data.getbyte(off) - bleed, 0].max)
      end
    end
    header = [cw, ch, FIRST, n].pack("S<4")
    File.binwrite(File.join(out_dir, "font_#{name}.bin"), header + data)
    puts "font_#{name}.bin #{cw}x#{ch} (#{data.bytesize} bytes)"
  end
end
