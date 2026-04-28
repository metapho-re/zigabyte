const std = @import("std");
const fs = std.fs;
const heap = std.heap;
const log = std.log;
const process = std.process;
const testing = std.testing;

const raw_mode = @import("raw_mode.zig");

pub fn main() !void {
    var gpa = heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    const args = try process.argsAlloc(allocator);
    defer process.argsFree(allocator, args);

    if (args.len > 2) {
        log.info("Usage: zigabyte [directory]", .{});
        return;
    }

    const directory_path = if (args.len > 1) args[1] else ".";

    var directory_handle = fs.cwd().openDir(directory_path, .{}) catch |err| switch (err) {
        error.FileNotFound => {
            log.err("Directory not found: {s}", .{directory_path});
            return;
        },
        error.AccessDenied => {
            log.err("Access denied: {s}", .{directory_path});
            return;
        },
        error.NotDir => {
            log.err("Not a directory: {s}", .{directory_path});
            return;
        },
        else => {
            log.err("Failed to open {s}: {}", .{ directory_path, err });
            return;
        },
    };
    defer directory_handle.close();

    const original_termios = try raw_mode.enableRawMode();
    defer raw_mode.disableRawMode(original_termios) catch |err| {
        log.err("{}", .{err});
    };
}

test {
    testing.refAllDecls(@This());
}
