// The harness's trivial program, Zig comparison point: `hello <name>` prints
// "hello <name>" and a newline and exits zero.
const std = @import("std");

pub fn main(init: std.process.Init) !void {
    var args = std.process.Args.Iterator.init(init.minimal.args);
    _ = args.next();
    const name = args.next() orelse "";
    var buf: [256]u8 = undefined;
    const line = try std.fmt.bufPrint(&buf, "hello {s}\n", .{name});
    try std.Io.File.stdout().writeStreamingAll(init.io, line);
}
