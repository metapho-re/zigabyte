const std = @import("std");
const debug = std.debug;
const testing = std.testing;
const Init = std.process.Init;
const Io = std.Io;
const Writer = std.Io.Writer;

const scanner = @import("scanner.zig");
const terminal = @import("terminal.zig");

pub fn main(init: Init) !void {
    var stderr_buffer: [1024]u8 = undefined;
    var stderr_writer = Io.File.stderr().writer(init.io, &stderr_buffer);

    const stderr = &stderr_writer.interface;
    const allocator = init.gpa;
    const args = init.minimal.args;

    var args_iterator = args.iterate();
    defer args_iterator.deinit();

    _ = args_iterator.skip();

    const arg = args_iterator.next();

    if (args_iterator.next() != null) {
        fatal(stderr, "Usage: zigabyte [directory]", .{});
        return;
    }

    const dir_path = if (arg) |value| value else ".";

    var dir_handle = Io.Dir.cwd().openDir(init.io, dir_path, .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound => {
            fatal(stderr, "Directory not found: {s}", .{dir_path});
            return;
        },
        error.AccessDenied => {
            fatal(stderr, "Access denied: {s}", .{dir_path});
            return;
        },
        error.NotDir => {
            fatal(stderr, "Not a directory: {s}", .{dir_path});
            return;
        },
        else => {
            fatal(stderr, "Failed to open {s}: {}", .{ dir_path, err });
            return;
        },
    };
    defer dir_handle.close(init.io);

    const root_node = try scanner.getNode(allocator, init.io, &dir_handle, dir_path);
    defer root_node.deinit(allocator);

    const original_termios = try terminal.enableRawMode();
    defer terminal.disableRawMode(original_termios) catch |err| {
        debug.print("{}", .{err});
    };

    terminal.registerResizeEventHandler();
}

fn fatal(stderr: *Writer, comptime fmt: []const u8, args: anytype) void {
    stderr.print(fmt, args) catch {};
    stderr.flush() catch {};
}

test {
    testing.refAllDecls(@This());
}
