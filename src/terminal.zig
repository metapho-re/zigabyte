const std = @import("std");
const atomic = std.atomic;
const mem = std.mem;
const os = std.os;
const posix = std.posix;
const testing = std.testing;
const Sigaction = posix.Sigaction;
const Termios = std.posix.termios;
const Winsize = std.posix.winsize;

var resize_event_flag = atomic.Value(bool).init(false);

fn handleResizeEvent(_: os.linux.SIG) callconv(.c) void {
    resize_event_flag.store(true, .release);
}

pub fn registerResizeEventHandler() void {
    var sigaction: Sigaction = .{
        .handler = .{ .handler = handleResizeEvent },
        .mask = posix.sigemptyset(),
        .flags = 0,
    };

    posix.sigaction(posix.SIG.WINCH, &sigaction, null);
}

fn getWindowSize() !Winsize {
    var winsize: Winsize = .{ .row = 0, .col = 0, .xpixel = 0, .ypixel = 0 };

    const return_code = posix.system.ioctl(posix.STDOUT_FILENO, posix.T.IOCGWINSZ, @intFromPtr(&winsize));

    return if (return_code != 0) error.IoctlError else winsize;
}

fn getResizeEventFlag() bool {
    if (resize_event_flag.load(.acquire)) {
        resize_event_flag.store(false, .release);

        return true;
    }

    return false;
}

pub fn enableRawMode() !Termios {
    const original_termios = try posix.tcgetattr(posix.STDIN_FILENO);

    var new_termios = original_termios;

    applyRawFlags(&new_termios);

    try posix.tcsetattr(posix.STDIN_FILENO, .FLUSH, new_termios);

    return original_termios;
}

pub fn disableRawMode(original_termios: Termios) !void {
    try posix.tcsetattr(posix.STDIN_FILENO, .FLUSH, original_termios);
}

fn applyRawFlags(termios: *Termios) void {
    termios.cc[@intFromEnum(posix.V.MIN)] = 0;
    termios.cc[@intFromEnum(posix.V.TIME)] = 1;
    termios.iflag.ICRNL = false;
    termios.iflag.IXON = false;
    termios.lflag.ECHO = false;
    termios.lflag.ICANON = false;
    termios.lflag.ISIG = false;
    termios.lflag.IEXTEN = false;
    termios.oflag.OPOST = false;
}

test "getResizeEventFlag returns true once after a resize event" {
    resize_event_flag.store(false, .release);

    try testing.expectEqual(getResizeEventFlag(), false);

    resize_event_flag.store(true, .release);

    try testing.expectEqual(getResizeEventFlag(), true);
    try testing.expectEqual(getResizeEventFlag(), false);
    try testing.expectEqual(resize_event_flag.load(.acquire), false);
}

test "applyRawFlags disables all raw-mode flags" {
    var test_termios = mem.zeroes(Termios);

    test_termios.cc[@intFromEnum(posix.V.MIN)] = 42;
    test_termios.cc[@intFromEnum(posix.V.TIME)] = 42;
    test_termios.iflag.ICRNL = true;
    test_termios.iflag.IXON = true;
    test_termios.lflag.ECHO = true;
    test_termios.lflag.ICANON = true;
    test_termios.lflag.ISIG = true;
    test_termios.lflag.IEXTEN = true;
    test_termios.oflag.OPOST = true;

    applyRawFlags(&test_termios);

    try testing.expectEqual(0, test_termios.cc[@intFromEnum(posix.V.MIN)]);
    try testing.expectEqual(1, test_termios.cc[@intFromEnum(posix.V.TIME)]);
    try testing.expectEqual(false, test_termios.iflag.ICRNL);
    try testing.expectEqual(false, test_termios.iflag.IXON);
    try testing.expectEqual(false, test_termios.lflag.ECHO);
    try testing.expectEqual(false, test_termios.lflag.ICANON);
    try testing.expectEqual(false, test_termios.lflag.ISIG);
    try testing.expectEqual(false, test_termios.lflag.IEXTEN);
    try testing.expectEqual(false, test_termios.oflag.OPOST);
}
