const std = @import("std");
const log = std.log;
const testing = std.testing;

const raw_mode = @import("raw_mode.zig");

pub fn main() !void {
    const original_termios = try raw_mode.enableRawMode();
    defer raw_mode.disableRawMode(original_termios) catch |err| {
        log.err("{}", .{err});
    };
}

test {
    testing.refAllDecls(@This());
}
