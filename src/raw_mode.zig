const std = @import("std");
const mem = std.mem;
const posix = std.posix;
const testing = std.testing;
const Termios = std.posix.termios;

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
    termios.iflag.ICRNL = false;
    termios.iflag.IXON = false;
    termios.lflag.ECHO = false;
    termios.lflag.ICANON = false;
    termios.lflag.ISIG = false;
    termios.lflag.IEXTEN = false;
    termios.oflag.OPOST = false;
}

test "applyRawFlags disables all raw-mode flags" {
    var test_termios = mem.zeroes(Termios);

    test_termios.iflag.ICRNL = true;
    test_termios.iflag.IXON = true;
    test_termios.lflag.ECHO = true;
    test_termios.lflag.ICANON = true;
    test_termios.lflag.ISIG = true;
    test_termios.lflag.IEXTEN = true;
    test_termios.oflag.OPOST = true;

    applyRawFlags(&test_termios);

    try testing.expectEqual(false, test_termios.iflag.ICRNL);
    try testing.expectEqual(false, test_termios.iflag.IXON);
    try testing.expectEqual(false, test_termios.lflag.ECHO);
    try testing.expectEqual(false, test_termios.lflag.ICANON);
    try testing.expectEqual(false, test_termios.lflag.ISIG);
    try testing.expectEqual(false, test_termios.lflag.IEXTEN);
    try testing.expectEqual(false, test_termios.oflag.OPOST);
}
