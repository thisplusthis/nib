# nib

A tiny command-line calculator for programmers. Evaluate a 64-bit integer
expression and print the result in decimal, binary, octal, and hex at once.

```
$ nib "2 + 2 * 3"
╭────────────────────╮
│  decimal   8       │
│  binary    0b1000  │
│  octal     0o10    │
│  hex       0x8     │
╰────────────────────╯
```

Every line is a valid literal you can paste straight back into `nib`. Output is
colorized on a terminal and plain when piped or redirected (or when `NO_COLOR`
is set). Extra lines appear only when they add information — `unsigned` for
negatives, `char` for a printable ASCII byte:

```
$ nib 0x41                     $ nib "~0"
╭──────────────────────╮      │  decimal   -1                       │
│  decimal   65        │      │  unsigned  18446744073709551615     │
│  binary    0b100_0001│      │  binary    0b1111_1111_… (64 bits)  │
│  octal     0o101     │      │  octal     0o1777777777777777777777 │
│  hex       0x41      │      │  hex       0xffff_ffff_ffff_ffff    │
│  char      'A'       │      ╰─────────────────────────────────────╯
╰──────────────────────╯
```

## Build

Requires [Zig](https://ziglang.org) 0.16.0.

```
zig build              # binary at zig-out/bin/nib
zig build run -- "1 << 4"
zig build test
```

## Install

Build an optimized binary straight into a directory on your `PATH`
(`--prefix DIR` installs to `DIR/bin/`):

```
zig build --prefix ~/.local -Doptimize=ReleaseSafe   # -> ~/.local/bin/nib
```

## Usage

```
nib <expression>
```

Arguments are joined, so quoting is optional for plain arithmetic:

```
nib 0xff + 1
nib "0xff + 1"
```

Quote the expression when it contains shell metacharacters
(`& | ^ ~ << >> * ( )`), otherwise the shell will eat them:

```
nib "0xdead & 0xff00"
nib "1 << 20"
```

### Number formats

| Input     | Meaning        |
|-----------|----------------|
| `255`     | decimal        |
| `0xff`    | hexadecimal    |
| `0o755`   | octal          |
| `0b1010`  | binary         |
| `1_000`   | `_` separators |

### Operators

By precedence, tightest first (C order, left-associative). Use `( )` to group:

| Operators   | Description                    |
|-------------|--------------------------------|
| `~ -`       | bitwise not, negation (unary)  |
| `* / %`     | multiply, divide, remainder    |
| `+ -`       | add, subtract                  |
| `<< >>`     | shift left, shift right        |
| `&`         | bitwise and                    |
| `^`         | bitwise xor                    |
| `\|`        | bitwise or                     |

## Notes

- All math is 64-bit and wraps on overflow (two's-complement, like a CPU register).
- `/` is truncating integer division; `>>` is arithmetic (sign-extending); `<<` truncates overflow bits.
- Shift amounts must be 0–63.
- The `decimal` line is signed; `unsigned`, `binary`, `octal`, and `hex` show the two's-complement bit pattern.
- `binary` and long `hex` are grouped in fours with `_` for readability (and stay valid literals); `unsigned` and `char` appear only when meaningful.
