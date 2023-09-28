const std = @import("std");
const ascii = @import("std").ascii;
const fmt = @import("std").fmt;
const io = @import("std").io;
const heap = @import("std").heap;
const mem = @import("std").mem;
const Movement = @import("key.zig").Movement;
const Key = @import("key.zig").Key;
const Editor = @import("editor.zig").Editor;
const EditorState = @import("editor.zig").EditorState;
usingnamespace @import("std").os;

const stdin_fd = io.getStdIn().handle;
const stdin = io.getStdIn().reader();
const stdout = io.getStdOut().writer();

var gpa = heap.GeneralPurposeAllocator(.{}){};

pub fn main() anyerror!void {
    var args = std.process.args();
    _ = args.next();

    //var path = args.next() orelse {
    //    std.debug.print("Usage: ZED [filename]\n\n", .{});
    //    return error.NoFileName;
    //};

    var path = args.next() orelse "";

    var allocator = gpa.allocator();
    var edit = try Editor.init(allocator, path);
    try edit.enableRawMode();
    defer edit.disableRawMode();

    while (!edit.shutting_down) {
        try edit.updateWindowSize();
        try edit.refreshScreen();
        try edit.process();
    }

    //    editor.free();
    try stdout.writeAll("\x1b[2J");
    try stdout.writeAll("\x1b[H");
}
