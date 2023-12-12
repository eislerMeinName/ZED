const std = @import("std");
const heap = std.heap;
const Key = @import("key").Key;
const Editor = @import("editor.zig").Editor;
const EditorState = @import("editor.zig").EditorState;
const io = std.io;

const stdout = io.getStdOut().writer();

var gpa = heap.GeneralPurposeAllocator(.{}){};

pub fn main() anyerror!void {
    var args = std.process.args();
    _ = args.next();

    var path = args.next() orelse "";

    var allocator = gpa.allocator();
    // defer _ = gpa.deinit();

    var edit = try Editor.init(allocator, path);
    try edit.enableRawMode();
    defer edit.deinit();

    while (!edit.shutting_down) {
        try edit.updateWindowSize();
        try edit.refreshScreen();
        try edit.process();
    }

    try stdout.writeAll("\x1b[2J");
    try stdout.writeAll("\x1b[H");
    try stdout.writeAll("\x1B[2J\x1B[H");
}
