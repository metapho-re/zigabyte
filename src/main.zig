const std = @import("std");
const debug = std.debug;
const fs = std.fs;
const heap = std.heap;
const process = std.process;
const testing = std.testing;
const Writer = std.io.Writer;

const raw_mode = @import("raw_mode.zig");
const scanner = @import("scanner.zig");

pub fn main() !void {
    var stderr_buffer: [1024]u8 = undefined;
    var stderr_writer = fs.File.stderr().writer(&stderr_buffer);

    const stderr = &stderr_writer.interface;

    var gpa = heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    const args = try process.argsAlloc(allocator);
    defer process.argsFree(allocator, args);

    if (args.len > 2) {
        fatal(stderr, "Usage: zigabyte [directory]", .{});
        return;
    }

    const dir_path = if (args.len > 1) args[1] else ".";

    var dir_handle = fs.cwd().openDir(dir_path, .{ .iterate = true }) catch |err| switch (err) {
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
    defer dir_handle.close();

    const root_node = try scanner.getNode(allocator, &dir_handle, dir_path);
    defer root_node.deinit(allocator);

    const original_termios = try raw_mode.enableRawMode();
    defer raw_mode.disableRawMode(original_termios) catch |err| {
        debug.print("{}", .{err});
    };
}

fn fatal(stderr: *Writer, comptime fmt: []const u8, args: anytype) void {
    stderr.print(fmt, args) catch {};
    stderr.flush() catch {};
}

test {
    testing.refAllDecls(@This());
}
