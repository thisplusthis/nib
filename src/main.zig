const std = @import("std");
const nib = @import("nib");

const Palette = struct {
    dim: []const u8 = "",
    bold: []const u8 = "",
    reset: []const u8 = "",
};
const ansi: Palette = .{ .dim = "\x1b[2m", .bold = "\x1b[1m", .reset = "\x1b[0m" };
const plain: Palette = .{};

const Row = struct { label: []const u8, value: []const u8 };

/// Write `prefix` then `digits` grouped every `n` into `buf` (e.g. "0xffff_ffff").
fn radix(buf: []u8, prefix: []const u8, digits: []const u8, n: usize) []const u8 {
    @memcpy(buf[0..prefix.len], prefix);
    const g = nib.group(buf[prefix.len..], digits, n);
    return buf[0 .. prefix.len + g.len];
}

fn printFormats(w: *std.Io.Writer, val: i64, c: Palette) !void {
    const bits: u64 = @bitCast(val); // two's-complement bit pattern

    var rows: [6]Row = undefined;
    var n: usize = 0;

    var dbuf: [24]u8 = undefined;
    rows[n] = .{ .label = "decimal", .value = try std.fmt.bufPrint(&dbuf, "{d}", .{val}) };
    n += 1;

    var ubuf: [24]u8 = undefined;
    if (val < 0) { // signed value's unsigned interpretation
        rows[n] = .{ .label = "unsigned", .value = try std.fmt.bufPrint(&ubuf, "{d}", .{bits}) };
        n += 1;
    }

    var braw: [64]u8 = undefined;
    var bbuf: [96]u8 = undefined;
    rows[n] = .{ .label = "binary", .value = radix(&bbuf, "0b", try std.fmt.bufPrint(&braw, "{b}", .{bits}), 4) };
    n += 1;

    var obuf: [32]u8 = undefined;
    rows[n] = .{ .label = "octal", .value = try std.fmt.bufPrint(&obuf, "0o{o}", .{bits}) };
    n += 1;

    var xraw: [16]u8 = undefined;
    var xbuf: [24]u8 = undefined;
    rows[n] = .{ .label = "hex", .value = radix(&xbuf, "0x", try std.fmt.bufPrint(&xraw, "{x}", .{bits}), 4) };
    n += 1;

    var cbuf: [8]u8 = undefined;
    if (val >= 0x20 and val <= 0x7e) { // printable ASCII
        rows[n] = .{ .label = "char", .value = try std.fmt.bufPrint(&cbuf, "'{c}'", .{@as(u8, @intCast(val))}) };
        n += 1;
    }
    const used = rows[0..n];

    const label_w: usize = 8; // widest label ("unsigned")
    var value_w: usize = 0;
    for (used) |r| value_w = @max(value_w, r.value.len);
    const inner = 2 + label_w + 2 + value_w + 2; // margins + label + gap + value

    try w.print("{s}╭", .{c.dim});
    try w.splatBytesAll("─", inner);
    try w.print("╮{s}\n", .{c.reset});

    for (used) |r| {
        try w.print("{s}│{s}  ", .{ c.dim, c.reset });
        try w.print("{s}{s}{s}", .{ c.dim, r.label, c.reset });
        try w.splatByteAll(' ', label_w - r.label.len + 2);
        try w.print("{s}{s}{s}", .{ c.bold, r.value, c.reset });
        try w.splatByteAll(' ', value_w - r.value.len + 2);
        try w.print("{s}│{s}\n", .{ c.dim, c.reset });
    }

    try w.print("{s}╰", .{c.dim});
    try w.splatBytesAll("─", inner);
    try w.print("╯{s}\n", .{c.reset});
}

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();

    var args_iter = try std.process.Args.Iterator.initAllocator(init.minimal.args, init.gpa);
    defer args_iter.deinit();
    _ = args_iter.skip();

    // Join all argv so both `nib 2 + 2 * 3` and `nib "2 + 2 * 3"` work.
    var parts: std.ArrayList([]const u8) = .empty;
    while (args_iter.next()) |a| try parts.append(arena, a);

    if (parts.items.len == 0) {
        std.debug.print(
            \\Usage: nib <expr>
            \\  nib 0xff + 1            decimal, 0x hex, 0o octal, 0b binary, 1_000
            \\  nib "0xff & 0x0f"       & | ^ ~ << >>  (quote: the shell eats these)
            \\
        , .{});
        return;
    }
    const expr = try std.mem.join(arena, " ", parts.items);

    const result = nib.eval(expr) catch |err| {
        std.debug.print("Error: {s}\n", .{switch (err) {
            error.ExpectedNumber => "expected a number",
            error.SyntaxError => "malformed expression",
            error.BadNumber => "not a valid number",
            error.DivByZero => "division by zero",
            error.BadShift => "shift amount must be 0-63",
        }});
        std.process.exit(1);
    };

    // Color only on a real terminal, and never when NO_COLOR is set.
    const stdout_file = std.Io.File.stdout();
    const color = (stdout_file.isTty(init.io) catch false) and
        init.minimal.environ.getPosix("NO_COLOR") == null;

    var buf: [512]u8 = undefined;
    var stdout = stdout_file.writerStreaming(init.io, &buf);
    const out = &stdout.interface;
    try printFormats(out, result, if (color) ansi else plain);
    try out.flush();
}
