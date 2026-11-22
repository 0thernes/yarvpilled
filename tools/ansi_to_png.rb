# frozen_string_literal: true

# Renders the last frame of a captured `--tui` session (ANSI truecolor) to a
# PNG so the terminal mode can be previewed without a terminal.
#   ruby yarv_brain.rb --tui --frames=120 > /tmp/tui.txt
#   ruby tools/ansi_to_png.rb /tmp/tui.txt out/tui.png
$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "yarvpilled/gfx"

src, dst = ARGV
frame = File.read(src, encoding: "UTF-8").split("\e[H").last
cols = 132
rows = 40
cw = 6
ch = 12
c = Yarvpilled::Canvas.new(cols * cw, rows * ch)
c.fill([0, 0, 0])
fg = [200, 200, 200]
bg = [0, 0, 0]
x = y = 0
frame.scan(/\e\[([0-9;?]*)([A-Za-z])|(\n)|(.)/m) do |params, cmd, nl, char|
  if cmd
    next unless cmd == "m"

    p = params.split(";").map(&:to_i)
    if p[0] == 38 && p[1] == 2 then fg = p[2, 3]
    elsif p[0] == 48 && p[1] == 2 then bg = p[2, 3]
    elsif p == [0] || p.empty? then fg = [200, 200, 200]
                                    bg = [0, 0, 0]
    end
  elsif nl
    x = 0
    y += 1
  elsif char
    next if x >= cols || y >= rows

    if char == "\u2580"
      c.rect(x * cw, y * ch, cw, ch / 2, fg)
      c.rect(x * cw, y * ch + ch / 2, cw, ch / 2, bg)
    else
      c.rect(x * cw, y * ch, cw, ch, bg)
      c.text(char.ord < 128 ? char : (char == "\u2588" || char == "\u25A0" ? "#" : "?"), x * cw, y * ch, fg)
    end
    x += 1
  end
end
File.binwrite(dst, c.to_png)
