const Key = @import("key.zig").Key;
const Movement = @import("key.zig").Movement;
const std = @import("std");
const io = @import("std").io;
const os = std.os;
const stdin = io.getStdIn().reader();
const mem = @import("std").mem;
const heap = @import("std").heap;
const window = @import("window.zig");
const WindowSize = window.WindowSize;
const fmt = std.fmt;
const termios = os.termios;

const zed_version = "0.1";

pub const EditorState = enum { writing, controlling };

pub const StringArrayList = std.ArrayList([]u8);

const stdout = io.getStdOut().writer();
const stdin_fd = io.getStdIn().handle;

pub fn edit_panic(msg: []const u8, error_return_trace: ?*std.builtin.StackTrace) noreturn {
    stdout.writeAll("\x1b[2J") catch {};
    stdout.writeAll("\x1b[H") catch {};
    std.builtin.default_panic(msg, error_return_trace, 1000);
}

pub const Editor = struct {
    n_rows: u16,
    n_cols: u16,
    row_offset: usize,
    col_offset: usize,
    rows: StringArrayList,
    cursor: @Vector(2, i16),
    offset: @Vector(2, i16),
    shutting_down: bool,
    state: EditorState,
    control: u8,
    allocator: mem.Allocator,
    orig_termios: termios,

    const Self = @This();

    pub fn init(allocator: mem.Allocator) !*Editor {
        const ws = try window.getWindowSize();
        var edit = try allocator.create(Self);
        edit.* = .{
            .n_rows = ws.rows,
            .n_cols = ws.cols,
            .cursor = @Vector(2, i16){ 0, 0 },
            .offset = @Vector(2, i16){ 0, 0 },
            .rows = StringArrayList.init(allocator),
            .row_offset = 0,
            .col_offset = 0,
            .shutting_down = false,
            .control = ' ',
            .state = EditorState.writing,
            .allocator = allocator,
            .orig_termios = undefined,
        };
        return edit;
    }

    pub fn enableRawMode(self: *Self) !void {
        self.orig_termios = try os.tcgetattr(stdin_fd);
        var raw = self.orig_termios;
        raw.iflag &= ~(os.linux.BRKINT | os.linux.ICRNL | os.linux.INPCK | os.linux.ISTRIP | os.linux.IXON);
        raw.oflag &= ~(os.linux.OPOST);
        raw.cflag |= os.linux.CS8;
        raw.lflag &= ~(os.linux.ECHO | os.linux.ICANON | os.linux.IEXTEN | os.linux.ISIG);
        raw.cc[4] = 0;
        raw.cc[6] = 1;
        try os.tcsetattr(stdin_fd, os.linux.TCSA.FLUSH, raw);
    }

    pub fn disableRawMode(self: *Self) void {
        os.tcsetattr(stdin_fd, os.TCSA.FLUSH, self.orig_termios) catch edit_panic("tcsetattr", null);
    }

    fn transition(self: *Editor, input: u8) void {
        switch (self.state) {
            EditorState.writing => {
                if (input == '\x1b') {
                    self.state = EditorState.controlling;
                }
            },
            EditorState.controlling => {
                if (input == '\x1b') {
                    self.state = EditorState.controlling;
                } else if (input == ':') {
                    self.control = ':';
                } else if (input == 'x' and self.control == ':') {
                    self.shutting_down = true;
                }
            },
        }
    }

    pub fn process(self: *Editor) !void {
        const key = try self.readKey();
        switch (key) {
            .char => |char| self.transition(char),
            .movement => |m| self.moveCursor(m),
            .delete => {},
        }
    }

    fn drawRows(self: *Editor, writer: anytype) !void {
        var y: usize = 0;
        while (y < self.n_rows) : (y += 1) {
            const file_row = y + self.row_offset;
            if (file_row >= self.rows.items.len) {
                if (self.rows.items.len == 0 and y == self.n_rows / 3) {
                    var welcome = try fmt.allocPrint(self.allocator, "ZED -- version {s}", .{zed_version});
                    defer self.allocator.free(welcome);
                    if (welcome.len > self.n_cols) welcome = welcome[0..self.n_cols];
                    var padding = (self.n_cols - welcome.len) / 2;
                    if (padding > 0) {
                        try writer.writeAll("~");
                        padding -= 1;
                    }
                    while (padding > 0) : (padding -= 1) try writer.writeAll(" ");
                    try writer.writeAll(welcome);
                } else {
                    try writer.writeAll("~");
                }
            } else {
                const row = self.rows.items[file_row];
                var len = row.len;
                if (len > self.n_cols) len = self.n_cols;
                try writer.writeAll(row[0..len]);
            }
            try writer.writeAll("\x1b[K");
            if (y < self.n_rows - 1) try writer.writeAll("\r\n");
        }
    }

    pub fn refreshScreen(self: *Editor) !void {
        var buf = std.ArrayList(u8).init(self.allocator);
        defer buf.deinit();
        var writer = buf.writer();
        try writer.writeAll("\x1b[?25l");
        try writer.writeAll("\x1b[H");
        try self.drawRows(writer);
        try writer.print("\x1b[{d};{d}H", .{ (self.cursor[1] - @intCast(i16, self.row_offset)) + 1, self.cursor[0] + 1 });
        try writer.writeAll("\x1b[?25h");
        try stdout.writeAll(buf.items);
    }

    fn moveCursor(self: *Editor, movement: Movement) void {
        switch (movement) {
            .arr_left => {
                if (self.cursor[0] > 0) self.cursor[0] -= 1;
            },
            .arr_right => {
                if (self.cursor[0] < self.n_cols - 1) self.cursor[0] += 1;
            },
            .arr_up => {
                if (self.cursor[1] > 0) self.cursor[1] -= 1;
            },
            .arr_down => {
                if (self.cursor[1] < self.rows.items.len - 1) self.cursor[1] += 1;
            },
            else => unreachable,
        }
    }

    fn readKey(self: *Editor) !Key {
        const byte = try readByte();
        self.transition(byte);
        switch (byte) {
            '\x1b' => {
                // Schwachsinn
                const sec_byte = readByte() catch return Key{ .char = '\x1b' };
                // is expected to be \n
                if (sec_byte == 10) {
                    return Key{ .char = '\x1b' };
                }
            },
            'a' => if (self.state == EditorState.writing) return Key{ .movement = .arr_left },
            'd' => if (self.state == EditorState.writing) return Key{ .movement = .arr_right },
            's' => if (self.state == EditorState.writing) return Key{ .movement = .arr_down },
            'w' => if (self.state == EditorState.writing) return Key{ .movement = .arr_up },
            else => {},
        }
        return Key{ .char = byte };
    }

    fn readByte() !u8 {
        var buffer: [1]u8 = undefined;
        _ = try stdin.read(buffer[0..]);
        return buffer[0];
    }
};
