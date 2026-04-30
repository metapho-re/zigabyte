const std = @import("std");
const heap = std.heap;
const posix = std.posix;
const testing = std.testing;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const Dir = std.fs.Dir;

const Node = struct {
    name: []const u8,
    size: u64,
    children: ?[]Node = null,

    pub fn isDir(self: Node) bool {
        return self.children != null;
    }

    pub fn init(allocator: Allocator, name: []const u8, size: u64, children: ?[]Node) !Node {
        return Node{
            .name = try allocator.dupe(u8, name),
            .size = size,
            .children = children,
        };
    }

    pub fn deinit(self: Node, allocator: Allocator) void {
        if (self.children) |children| {
            if (children.len != 0) {
                for (children) |child| {
                    child.deinit(allocator);
                }

                allocator.free(children);
            }
        }

        allocator.free(self.name);
    }
};

pub fn getNode(allocator: Allocator, dir_handle: *Dir, name: []const u8) !Node {
    var total_size: u64 = 0;
    var iterator = dir_handle.iterate();
    var children_list = try ArrayList(Node).initCapacity(allocator, 16);
    errdefer {
        for (children_list.items) |child| {
            child.deinit(allocator);
        }

        children_list.deinit(allocator);
    }

    while (try iterator.next()) |entry| {
        switch (entry.kind) {
            .file => {
                const file_stat = dir_handle.statFile(entry.name) catch continue;
                const node = try Node.init(
                    allocator,
                    entry.name,
                    file_stat.size,
                    null,
                );

                try children_list.append(allocator, node);

                total_size += file_stat.size;
            },
            .directory => {
                var subdir_handle = dir_handle.openDir(
                    entry.name,
                    .{ .iterate = true },
                ) catch continue;
                defer subdir_handle.close();

                const node = try getNode(
                    allocator,
                    &subdir_handle,
                    entry.name,
                );

                try children_list.append(
                    allocator,
                    node,
                );

                total_size += node.size;
            },
            else => {},
        }
    }

    const children =
        if (children_list.items.len > 0)
            try children_list.toOwnedSlice(allocator)
        else blk: {
            children_list.deinit(allocator);
            break :blk @as(?[]Node, &.{});
        };

    return Node.init(
        allocator,
        name,
        total_size,
        children,
    );
}

test "Node.init / Node.deinit — create a node with init, verify fields, call deinit" {
    const file_node = try Node.init(testing.allocator, "test_file", 4096, null);
    defer file_node.deinit(testing.allocator);

    const dir_node = try Node.init(testing.allocator, "test_dir", 0, &.{});
    defer dir_node.deinit(testing.allocator);

    try testing.expectEqualStrings(dir_node.name, "test_dir");
    try testing.expectEqual(dir_node.size, 0);
    try testing.expectEqual(dir_node.isDir(), true);
    try testing.expectEqual(dir_node.children.?.len, 0);

    try testing.expectEqualStrings(file_node.name, "test_file");
    try testing.expectEqual(file_node.size, 4096);
    try testing.expectEqual(file_node.isDir(), false);
    try testing.expectEqual(file_node.children, null);
}

test "Node.isDir — true for nodes with children, false for nodes without" {
    const file_node = try Node.init(testing.allocator, "file", 100, null);
    defer file_node.deinit(testing.allocator);

    const empty_dir = try Node.init(testing.allocator, "empty_dir", 0, &.{});
    defer empty_dir.deinit(testing.allocator);

    const child = try Node.init(testing.allocator, "child", 50, null);
    const children = try testing.allocator.alloc(Node, 1);

    children[0] = child;

    const non_empty_dir = try Node.init(testing.allocator, "non_empty_dir", 50, children);
    defer non_empty_dir.deinit(testing.allocator);

    try testing.expectEqual(file_node.isDir(), false);
    try testing.expectEqual(empty_dir.isDir(), true);
    try testing.expectEqual(non_empty_dir.isDir(), true);
}

test "getNode on empty directory — verify children is non-null, size is 0, and no memory leaks" {
    var tmp_dir = testing.tmpDir(.{ .access_sub_paths = true, .iterate = true });
    defer tmp_dir.cleanup();

    const node = try getNode(testing.allocator, &tmp_dir.dir, "test_dir");
    defer node.deinit(testing.allocator);

    try testing.expectEqualStrings(node.name, "test_dir");
    try testing.expectEqual(node.size, 0);
    try testing.expectEqual(node.isDir(), true);
    try testing.expectEqual(node.children.?.len, 0);
}

test "getNode on directory with files — verify size matches the sum and child count is correct" {
    var tmp_dir = testing.tmpDir(.{ .access_sub_paths = true, .iterate = true });
    defer tmp_dir.cleanup();

    var file1 = try tmp_dir.dir.createFile("file1", .{ .read = true });
    _ = try file1.write("Zig is a general-purpose programming language and toolchain...");
    file1.close();

    var file2 = try tmp_dir.dir.createFile("file2", .{ .read = true });
    _ = try file2.write("I am writing Zig code like all the cool kids!");
    file2.close();

    const node = try getNode(testing.allocator, &tmp_dir.dir, "test_dir");
    defer node.deinit(testing.allocator);

    try testing.expectEqualStrings(node.name, "test_dir");
    try testing.expectEqual(node.size, 107);
    try testing.expectEqual(node.isDir(), true);
    try testing.expectEqual(node.children.?.len, 2);
}

test "getNode with nested directories — verify recursive scanning produces correct structure and accumulated sizes" {
    var tmp_dir = testing.tmpDir(.{ .access_sub_paths = true, .iterate = true });
    defer tmp_dir.cleanup();

    var file1 = try tmp_dir.dir.createFile("root_file", .{ .read = true });
    _ = try file1.write("Zig is a general-purpose programming language and toolchain...");
    file1.close();

    try tmp_dir.dir.makeDir("subdir");

    var subdir = try tmp_dir.dir.openDir("subdir", .{});
    defer subdir.close();

    var file2 = try subdir.createFile("nested_file", .{ .read = true });
    _ = try file2.write("...for maintaining robust, optimal, and reusable software.");
    file2.close();

    const node = try getNode(testing.allocator, &tmp_dir.dir, "root");
    defer node.deinit(testing.allocator);

    try testing.expectEqualStrings(node.name, "root");
    try testing.expectEqual(node.size, 120);
    try testing.expectEqual(node.isDir(), true);
    try testing.expectEqual(node.children.?.len, 2);

    try testing.expectEqualStrings(node.children.?[0].name, "subdir");
    try testing.expectEqual(node.children.?[0].size, 58);
    try testing.expectEqual(node.children.?[0].isDir(), true);
    try testing.expectEqual(node.children.?[0].children.?.len, 1);

    try testing.expectEqualStrings(node.children.?[1].name, "root_file");
    try testing.expectEqual(node.children.?[1].size, 62);
    try testing.expectEqual(node.children.?[1].isDir(), false);
    try testing.expectEqual(node.children.?[1].children, null);

    try testing.expectEqualStrings(node.children.?[0].children.?[0].name, "nested_file");
    try testing.expectEqual(node.children.?[0].children.?[0].size, 58);
    try testing.expectEqual(node.children.?[0].children.?[0].isDir(), false);
    try testing.expectEqual(node.children.?[0].children.?[0].children, null);
}

test "getNode with inaccessible entries — verify skipped without error and other entries are still scanned" {
    var tmp_dir = testing.tmpDir(.{ .access_sub_paths = true, .iterate = true });
    defer tmp_dir.cleanup();

    var file1 = try tmp_dir.dir.createFile("accessible_file", .{ .read = true });
    _ = try file1.write("accessible content");
    file1.close();

    try tmp_dir.dir.makeDir("inaccessible_dir");
    try posix.fchmodat(tmp_dir.dir.fd, "inaccessible_dir", 0, 0);

    const node = try getNode(testing.allocator, &tmp_dir.dir, "test_dir");
    defer node.deinit(testing.allocator);

    try testing.expectEqualStrings(node.name, "test_dir");
    try testing.expectEqual(node.size, 18);
    try testing.expectEqual(node.isDir(), true);
    try testing.expectEqual(node.children.?.len, 1);

    try testing.expectEqualStrings(node.children.?[0].name, "accessible_file");
    try testing.expectEqual(node.children.?[0].size, 18);
    try testing.expectEqual(node.children.?[0].isDir(), false);
    try testing.expectEqual(node.children.?[0].children, null);
}

test "getNode skips symlinks and other non-file/non-directory entries" {
    var tmp_dir = testing.tmpDir(.{ .access_sub_paths = true, .iterate = true });
    defer tmp_dir.cleanup();

    var file1 = try tmp_dir.dir.createFile("real_file", .{ .read = true });
    _ = try file1.write("real content");
    file1.close();

    try tmp_dir.dir.symLink("real_file", "a_symlink", .{});

    const node = try getNode(testing.allocator, &tmp_dir.dir, "test_dir");
    defer node.deinit(testing.allocator);

    try testing.expectEqualStrings(node.name, "test_dir");
    try testing.expectEqual(node.size, 12);
    try testing.expectEqual(node.isDir(), true);
    try testing.expectEqual(node.children.?.len, 1);

    try testing.expectEqualStrings(node.children.?[0].name, "real_file");
    try testing.expectEqual(node.children.?[0].size, 12);
    try testing.expectEqual(node.children.?[0].isDir(), false);
    try testing.expectEqual(node.children.?[0].children, null);
}

test "getNode errdefer cleanup on allocation failure — use FailingAllocator, verify no memory leaks" {
    var tmp_dir = testing.tmpDir(.{ .access_sub_paths = true, .iterate = true });
    defer tmp_dir.cleanup();

    var file1 = try tmp_dir.dir.createFile("file1", .{ .read = true });
    _ = try file1.write("Zig is a general-purpose programming language and toolchain...");
    file1.close();

    var file2 = try tmp_dir.dir.createFile("file2", .{ .read = true });
    _ = try file2.write("...for maintaining robust, optimal, and reusable software.");
    file2.close();

    var failing = testing.FailingAllocator.init(testing.allocator, .{ .fail_index = 2 });

    try testing.expectError(
        error.OutOfMemory,
        getNode(failing.allocator(), &tmp_dir.dir, "test_dir"),
    );
}

test "Node.init name is independently allocated — mutating source buffer does not affect node name" {
    var name_buf: [7]u8 = "Ziguana".*;

    const node = try Node.init(testing.allocator, &name_buf, 100, null);
    defer node.deinit(testing.allocator);

    name_buf[0] = 'X';

    try testing.expectEqualStrings(node.name, "Ziguana");
}
