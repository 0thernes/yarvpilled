# Security Policy

## Supported versions

| Version | Supported |
|---|---|
| 0.2.x | yes |
| < 0.2 | no |

## Scope

yarvpilled is a local simulation and visualizer. The parts with a real attack surface are:

- `server.rb`, a small stdlib `TCPServer` serving a static page and an SSE stream. It binds to
  `127.0.0.1` by default and is not meant to be exposed to the internet.
- The native extension (`ext/`), which handles memory directly.
- Genome compilation: genomes are generated internally from a fixed grammar and compiled with
  `RubyVM::InstructionSequence`. The project never evaluates user-supplied source code. If you
  find a way to make it do so, please report it.

## Reporting a vulnerability

Please **do not open a public issue**. Instead:

- use GitHub's private reporting: <https://github.com/0thernes/yarvpilled/security/advisories/new>, or
- email **0_0@0thernes.art** with the subject `yarvpilled security`.

Include the version (`ruby yarv_brain.rb --version`), your OS and Ruby version, and steps to
reproduce. You can expect an acknowledgement within 7 days. A fix or mitigation plan will
follow once the issue is confirmed, and you will be credited unless you prefer otherwise.
