//! zc — 64-bit integer expression evaluator for programmers.
//!
//! Radixes: decimal, `0x` hex, `0o` octal, `0b` binary, `_` digit separators.
//! Operators, by precedence (tight → loose), C order, left-associative:
//!   unary  ~ -
//!   * / %
//!   + -
//!   << >>
//!   &
//!   ^
//!   |
//! Arithmetic wraps (two's-complement, like a CPU register); `>>` is
//! arithmetic (sign-extending); `<<` truncates overflow. No parentheses.
const std = @import("std");

pub const EvalError = error{
    SyntaxError,
    ExpectedNumber,
    BadNumber,
    DivByZero,
    BadShift,
};

pub fn eval(expr: []const u8) EvalError!i64 {
    var p = try Parser.init(expr);
    const result = try p.parseExpr(0);
    if (p.cur != .end) return error.SyntaxError; // trailing tokens
    return result;
}

/// Insert `_` every `n` digits, counting from the right, so the output is a
/// valid literal (e.g. "ffffffff" -> "ffff_ffff"). Writes into `buf` and
/// returns the slice; `buf` must hold `digits.len` plus the separators.
pub fn group(buf: []u8, digits: []const u8, n: usize) []const u8 {
    var o: usize = 0;
    for (digits, 0..) |d, i| {
        if (i != 0 and (digits.len - i) % n == 0) {
            buf[o] = '_';
            o += 1;
        }
        buf[o] = d;
        o += 1;
    }
    return buf[0..o];
}

const Op = enum { bit_or, bit_xor, bit_and, shl, shr, add, sub, mul, div, rem, not };

const Tok = union(enum) { num: i64, op: Op, end };

const Lexer = struct {
    s: []const u8,
    i: usize = 0,

    fn next(l: *Lexer) EvalError!Tok {
        while (l.i < l.s.len and std.ascii.isWhitespace(l.s[l.i])) l.i += 1;
        if (l.i >= l.s.len) return .end;

        const c = l.s[l.i];
        if (std.ascii.isDigit(c)) return l.number();

        l.i += 1;
        return switch (c) {
            '+' => .{ .op = .add },
            '-' => .{ .op = .sub },
            '*' => .{ .op = .mul },
            '/' => .{ .op = .div },
            '%' => .{ .op = .rem },
            '&' => .{ .op = .bit_and },
            '|' => .{ .op = .bit_or },
            '^' => .{ .op = .bit_xor },
            '~' => .{ .op = .not },
            '<' => l.pair('<', .shl),
            '>' => l.pair('>', .shr),
            else => error.SyntaxError,
        };
    }

    /// Second half of a two-char operator (`<<`, `>>`).
    fn pair(l: *Lexer, ch: u8, op: Op) EvalError!Tok {
        if (l.i < l.s.len and l.s[l.i] == ch) {
            l.i += 1;
            return .{ .op = op };
        }
        return error.SyntaxError;
    }

    fn number(l: *Lexer) EvalError!Tok {
        const start = l.i;
        while (l.i < l.s.len and (std.ascii.isAlphanumeric(l.s[l.i]) or l.s[l.i] == '_')) l.i += 1;
        // base 0 auto-detects the 0x/0o/0b prefix; also accepts `_` separators.
        const n = std.fmt.parseInt(i64, l.s[start..l.i], 0) catch return error.BadNumber;
        return .{ .num = n };
    }
};

const Parser = struct {
    lex: Lexer,
    cur: Tok,

    fn init(s: []const u8) EvalError!Parser {
        var p = Parser{ .lex = .{ .s = s }, .cur = undefined };
        try p.advance();
        return p;
    }

    fn advance(p: *Parser) EvalError!void {
        p.cur = try p.lex.next();
    }

    /// Precedence climbing: fold binary operators whose left binding power is
    /// at least `min_bp` into the current left-hand value.
    fn parseExpr(p: *Parser, min_bp: u8) EvalError!i64 {
        var left = try p.parseUnary();
        while (p.cur == .op) {
            const op = p.cur.op;
            const bp = bindingPower(op) orelse break; // `~` has no infix form
            if (bp.l < min_bp) break;
            try p.advance();
            const right = try p.parseExpr(bp.r);
            left = try apply(op, left, right);
        }
        return left;
    }

    fn parseUnary(p: *Parser) EvalError!i64 {
        switch (p.cur) {
            .num => |n| {
                try p.advance();
                return n;
            },
            .op => |op| switch (op) {
                .not => {
                    try p.advance();
                    return ~(try p.parseUnary());
                },
                .sub => {
                    try p.advance();
                    return -%(try p.parseUnary());
                },
                else => return error.ExpectedNumber,
            },
            .end => return error.ExpectedNumber,
        }
    }
};

const Bp = struct { l: u8, r: u8 };

/// Left/right binding power. Left-associative → left < right. Returns null for
/// operators with no binary form.
fn bindingPower(op: Op) ?Bp {
    return switch (op) {
        .bit_or => .{ .l = 2, .r = 3 },
        .bit_xor => .{ .l = 4, .r = 5 },
        .bit_and => .{ .l = 6, .r = 7 },
        .shl, .shr => .{ .l = 8, .r = 9 },
        .add, .sub => .{ .l = 10, .r = 11 },
        .mul, .div, .rem => .{ .l = 12, .r = 13 },
        .not => null,
    };
}

fn apply(op: Op, a: i64, b: i64) EvalError!i64 {
    return switch (op) {
        .add => a +% b,
        .sub => a -% b,
        .mul => a *% b,
        .div => if (b == 0) error.DivByZero else @divTrunc(a, b),
        .rem => if (b == 0) error.DivByZero else @rem(a, b),
        .bit_and => a & b,
        .bit_or => a | b,
        .bit_xor => a ^ b,
        .shl => if (b < 0 or b > 63) error.BadShift else std.math.shl(i64, a, b),
        .shr => if (b < 0 or b > 63) error.BadShift else std.math.shr(i64, a, b),
        .not => unreachable,
    };
}

test "arithmetic and precedence" {
    try std.testing.expectEqual(@as(i64, 8), try eval("2 + 2 * 3"));
    try std.testing.expectEqual(@as(i64, 1), try eval("7 - 2 * 3"));
    try std.testing.expectEqual(@as(i64, 2), try eval("10 / 2 % 3"));
    try std.testing.expectEqual(@as(i64, -6), try eval("2 * 3 - 12"));
    try std.testing.expectEqual(@as(i64, 42), try eval("42"));
    try std.testing.expectEqual(@as(i64, -7), try eval("-7"));
}

test "radix input" {
    try std.testing.expectEqual(@as(i64, 255), try eval("0xff"));
    try std.testing.expectEqual(@as(i64, 10), try eval("0b1010"));
    try std.testing.expectEqual(@as(i64, 493), try eval("0o755"));
    try std.testing.expectEqual(@as(i64, 1000), try eval("1_000"));
    try std.testing.expectEqual(@as(i64, 256), try eval("0xff + 1"));
}

test "bitwise" {
    try std.testing.expectEqual(@as(i64, 0x0f), try eval("0xff & 0x0f"));
    try std.testing.expectEqual(@as(i64, 0xff), try eval("0xf0 | 0x0f"));
    try std.testing.expectEqual(@as(i64, 0xff), try eval("0xf0 ^ 0x0f"));
    try std.testing.expectEqual(@as(i64, 16), try eval("1 << 4"));
    try std.testing.expectEqual(@as(i64, 2), try eval("16 >> 3"));
    try std.testing.expectEqual(@as(i64, -1), try eval("~0"));
    // no spaces
    try std.testing.expectEqual(@as(i64, 0x0f), try eval("0xff&0x0f"));
    // precedence: & binds looser than +, tighter than |
    try std.testing.expectEqual(@as(i64, 0x1f), try eval("0x10 | 0x08 + 0x07"));
    try std.testing.expectEqual(@as(i64, 12), try eval("1 << 2 | 8"));
}

test "group" {
    var b: [96]u8 = undefined;
    try std.testing.expectEqualStrings("", group(&b, "", 4));
    try std.testing.expectEqualStrings("0", group(&b, "0", 4));
    try std.testing.expectEqualStrings("1000", group(&b, "1000", 4));
    try std.testing.expectEqualStrings("1111_1010", group(&b, "11111010", 4));
    try std.testing.expectEqualStrings("1_0000", group(&b, "10000", 4));
    try std.testing.expectEqualStrings("ffff_ffff_ffff_ffff", group(&b, "ffffffffffffffff", 4));
}

test "errors" {
    try std.testing.expectError(error.DivByZero, eval("1 / 0"));
    try std.testing.expectError(error.DivByZero, eval("1 % 0"));
    try std.testing.expectError(error.ExpectedNumber, eval("1 + +"));
    try std.testing.expectError(error.SyntaxError, eval("1 2"));
    try std.testing.expectError(error.ExpectedNumber, eval("1 +"));
    try std.testing.expectError(error.ExpectedNumber, eval(""));
    try std.testing.expectError(error.BadNumber, eval("0xzz"));
    try std.testing.expectError(error.BadShift, eval("1 << 99"));
    try std.testing.expectError(error.SyntaxError, eval("1 < 2"));
}
