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
const Row = @import("row.zig").Row;
const ArrayList = std.ArrayList;

const zed_version = "0.1";

pub const EditorState = enum { starting, writing, controlling };

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
    row_offset: usize = 0,
    col_offset: usize = 0,
    rows: ArrayList(Row),
    cursor: @Vector(2, i16),
    offset: @Vector(2, i16),
    shutting_down: bool,
    state: EditorState = .starting,
    control: Row,
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
            .rows = ArrayList(Row).init(allocator),
            .shutting_down = false,
            .control = Row{ .src = "", .render = "" },
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

    fn transition(self: *Editor, input: u8) !void {
        switch (self.state) {
            .writing => {
                if (input == '\x1b') {
                    self.state = EditorState.controlling;
                }
            },
            .controlling => {
                if (mem.eql(u8, self.control.render, ":x")) self.shutting_down = true;
                if (input == '\x1b' and self.control.render.len < 2) {
                    self.state = EditorState.writing;
                } else {
                    if (self.control.render.len < 2) {
                        const app = [1]u8{input};
                        try self.control.appendString(&app, self.allocator);
                    }
                }
            },
            .starting => {
                self.state = .writing;
            },
        }
    }

    fn delete(self: *Editor) !void {
        switch (self.state) {
            .starting => self.state = .writing,
            .controlling => try self.control.delCharAt(self.control.render.len, self.allocator),
            .writing => {},
        }
    }

    fn insertNewLine(self: *Editor) !void {
        var f_row = self.row_offset + @intCast(usize, self.cursor[1]);
        var f_col = self.col_offset + @intCast(usize, self.cursor[0]);

        if (f_row >= self.rows.items.len) {
            if (f_row == self.rows.items.len) {
                try self.insertRow(f_row, "");
                self.fixCursor();
            }
            return;
        }

        var row = &self.rows.items[f_row];

        if (f_col >= row.src.len) f_col = row.src.len;

        if (f_col == 0) {
            try self.insertRow(f_row, "");
        } else {
            try self.insertRow(f_row + 1, row.src[f_col..row.src.len]);

            var j: usize = 0;

            for (row.src[0..f_col]) |c| {
                row.src[j] = c;
                j += 1;
            }

            _ = self.allocator.resize(row.src, f_col);

            row.*.src.len = f_col;

            try row.updateRow(self.allocator);
        }

        self.fixCursor();
    }

    fn fixCursor(self: *Editor) void {
        if (self.cursor[1] == self.n_rows - 1) self.row_offset += 1 else self.cursor[1] += 1;

        self.cursor[0] = 0;
        self.col_offset = 0;
    }

    fn insertRow(self: *Editor, at: usize, buffer: []const u8) !void {
        if (at < 0 or at > self.rows.items.len) return;

        var row = Row{ .src = try self.allocator.dupe(u8, buffer), .render = try self.allocator.alloc(u8, buffer.len) };

        try row.updateRow(self.allocator);
        try self.rows.insert(at, row);
    }

    fn delRow(self: *Editor, at: usize) !void {
        if (at >= self.rows.items.len) return;

        _ = self.rows.orderedRemove(at);
    }

    fn delChar(self: *Editor) !void {
        var f_row = self.row_offset + @intCast(usize, self.cursor[1]);
        var f_col = self.col_offset + @intCast(usize, self.cursor[0]);

        if (self.rows.items.len < f_row or (f_col == 0 and f_row == 0)) return;

        const row = &self.rows.items[f_row];

        if (f_col == 0) {
            f_col = self.rows.items[f_row - 1].src.len;
            try row.appendString(row.src, self.allocator);
            try self.delRow(f_row);

            if (self.cursor[1] == 0) self.row_offset -= 1 else self.cursor[1] -= 1;
            self.cursor[0] = @intCast(i16, f_col);

            if (self.cursor[0] >= self.n_cols) {
                var shift: usize = self.n_cols - @intCast(usize, self.cursor[0]) + 1;
                self.cursor[0] -= @intCast(i16, shift);
                self.col_offset += shift;
            }
        } else {
            try row.delCharAt(f_col - 1, self.allocator);
            if (self.cursor[0] == 0 and self.col_offset > 0) {
                self.col_offset -= 1;
            } else {
                self.cursor[0] -= 1;
            }

            try row.updateRow(self.allocator);
        }
    }

    fn insertChar(self: *Editor, char: u8) !void {
        var f_row = self.row_offset + @intCast(usize, self.cursor[1]);
        var f_col = self.col_offset + @intCast(usize, self.cursor[0]);

        var i = self.rows.items.len;

        if (f_row >= self.rows.items.len) {
            //for (len..f_row + 1) |_| try self.insertRow(self.rows.items.len, "");
            while (i <= f_row) : (i += 1) {
                try self.insertRow(self.rows.items.len, "");
            }
        }

        const row = &self.rows.items[f_row];

        try row.insertCharAt(f_col, self.allocator, char);

        if (self.cursor[0] == self.n_cols - 1) self.col_offset += 1 else self.cursor[0] += 1;
    }

    fn processWriting(self: *Editor, input: u8) !void {
        switch (@intToEnum(Key, input)) {
            .enter => return try self.insertNewLine(),
            .arr_left, .arr_up, .arr_down, .arr_right => self.moveCursor(input),
            .esc => self.state = .controlling,
            .home => self.cursor[0] = 0,
            .del => try self.delChar(),
            else => try self.insertChar(input),
        }
    }

    fn processControlling(self: *Editor, input: u8) !void {
        switch (@intToEnum(Key, input)) {
            .esc => self.state = .writing,
            .del => {
                try self.control.delCharAt(self.control.src.len - 1, self.allocator);
            },
            .enter => {
                if (mem.eql(u8, self.control.render, ":x")) self.shutting_down = true;
            },
            .arr_left, .arr_up, .arr_down, .arr_right => self.moveCursor(input),
            else => {
                const app = [1]u8{input};
                try self.control.appendString(&app, self.allocator);
            },
        }
    }

    pub fn process(self: *Editor) !void {
        const key = try self.readKey();
        switch (self.state) {
            .starting => self.state = .writing,
            .writing => try self.processWriting(key),
            .controlling => try self.processControlling(key),
        }
    }

    fn drawRows(self: *Editor, writer: anytype) !void {
        switch (self.state) {
            .starting => try self.drawStarting(writer),
            .writing => try self.drawWriting(writer),
            .controlling => try self.drawControl(writer),
        }
        try self.drawBottom(writer);
    }

    fn calcBottomSpace(self: *Editor) usize {
        var i: u16 = 1;
        var number1 = self.cursor[0];
        while (number1 >= 10) : (number1 = @divFloor(number1, 10)) {
            i += 1;
        }

        var j: u16 = 1;
        var number2 = self.cursor[1];
        while (number2 >= 10) : (number2 = @divFloor(number2, 10)) {
            j += 1;
        }

        return 2 + i + j;
    }

    fn drawBottom(self: *Editor, writer: anytype) !void {
        var mode = try fmt.allocPrint(self.allocator, "ZED -- mode {s}", .{@tagName(self.state)});
        defer self.allocator.free(mode);
        const space = self.calcBottomSpace();
        var padding = self.n_cols - mode.len - space - self.control.render.len;
        try writer.writeAll(mode);
        while (padding > self.n_cols / 2) : (padding -= 1) try writer.writeAll(" ");
        try writer.writeAll(self.control.render);
        while (padding > 0) : (padding -= 1) try writer.writeAll(" ");
        const curs = try std.fmt.allocPrint(self.allocator, "{d}, {d}", .{ @intCast(i16, self.cursor[1]), @intCast(i16, self.cursor[0]) });
        try writer.writeAll(curs);
    }

    fn drawWriting(self: *Editor, writer: anytype) !void {
        var y: usize = 0;
        while (y < self.n_rows - 1) : (y += 1) {
            const row = y + self.row_offset;
            if (row >= self.rows.items.len) {
                try writer.writeAll("*");
            } else {
                var text = &self.rows.items[row];
                var len = text.render.len;
                if (len > self.n_cols) len = self.n_cols;
                try writer.writeAll(text.render[0..len]);
            }
            try writer.writeAll("\x1b[K");
            if (y < self.n_rows - 1) try writer.writeAll("\r\n");
        }
    }

    fn drawControl(self: *Editor, writer: anytype) !void {
        var y: usize = 0;
        while (y < self.n_rows - 1) : (y += 1) {
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
                var row = &self.rows.items[file_row];
                var len = row.render.len;
                if (len > self.n_cols) len = self.n_cols;
                try writer.writeAll(row.render[0..len]);
            }
            try writer.writeAll("\x1b[K");
            if (y < self.n_rows - 1) try writer.writeAll("\r\n");
        }
    }

    fn drawStarting(self: *Editor, writer: anytype) !void {
        var y: usize = 0;
        while (y < self.n_rows - 1) : (y += 1) {
            const row = y + self.row_offset;
            if (row >= self.rows.items.len and self.rows.items.len == 0 and y == self.n_rows / 3) {
                var welcome = try fmt.allocPrint(self.allocator, "ZED -- version {s}", .{zed_version});
                defer self.allocator.free(welcome);
                if (welcome.len > self.n_cols) welcome = welcome[0..self.n_cols];
                var padding = (self.n_cols - welcome.len) / 2;
                while (padding > 0) : (padding -= 1) try writer.writeAll(" ");
                try writer.writeAll(welcome);
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

    fn moveCursor(self: *Editor, movement: u8) void {
        switch (@intToEnum(Key, movement)) {
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
                if (self.cursor[1] < self.rows.items.len) self.cursor[1] += 1;
            },
            else => unreachable,
        }
    }

    fn readKey(self: *Editor) !u8 {
        if (self.state == .starting) {
            _ = try readByte();
            return @enumToInt(Key.arr_up);
        }
        const byte = try readByte();
        switch (byte) {
            @enumToInt(Key.esc) => {
                const byte2 = readByte() catch return @enumToInt(Key.esc);

                if (byte2 == '[') {
                    const byte3 = readByte() catch return @enumToInt(Key.esc);
                    switch (byte3) {
                        'A' => return @enumToInt(Key.arr_up),
                        'B' => return @enumToInt(Key.arr_down),
                        'C' => return @enumToInt(Key.arr_right),
                        'D' => return @enumToInt(Key.arr_left),
                        'H' => return @enumToInt(Key.home),
                        'F' => return @enumToInt(Key.end),
                        '0'...'9' => {
                            const byte4 = readByte() catch return @enumToInt(Key.esc);
                            if (byte4 == '~') {
                                switch (byte3) {
                                    '1' => return @enumToInt(Key.home),
                                    '2' => return @enumToInt(Key.del),
                                    '3' => return @enumToInt(Key.end),
                                    //'4' => return @enumToInt(Key.page_up),
                                    //'5' => return @enumToInt(Key.page_down),
                                    //'6' => return @enumToInt(Key.page_down),
                                    '7' => return @enumToInt(Key.home),
                                    '8' => return @enumToInt(Key.end),
                                    else => {},
                                }
                            }
                        },
                        else => {},
                    }
                } else if (byte2 == 'O') {
                    const byte5 = readByte() catch return @enumToInt(Key.esc);
                    switch (byte5) {
                        'H' => return @enumToInt(Key.home),
                        'F' => return @enumToInt(Key.end),
                        else => {},
                    }
                }

                return @enumToInt(Key.esc);
            },
            else => return byte,
        }

        return byte;
    }

    fn readKey2(self: *Editor) !Key {
        if (self.state == .starting) {
            const cc = try readByte();
            return Key{ .char = cc };
        }
        const c = try readByte();
        //return @intToEnum(Key,c);
        switch (c) {
            '\x1b' => {
                const c1 = readByte() catch return Key{ .char = '\x1b' };
                if (c1 == '[') {
                    const c2 = readByte() catch return Key{ .char = '\x1b' };
                    switch (c2) {
                        'A' => return Key{ .movement = .arr_up },
                        'B' => return Key{ .movement = .arr_down },
                        'C' => return Key{ .movement = .arr_right },
                        'D' => return Key{ .movement = .arr_left },
                        'F' => return Key{ .movement = .end_key },
                        'H' => return Key{ .movement = .home_key },
                        '1' => {
                            const c3 = readByte() catch return Key{ .char = '\x1b' };
                            if (c3 == '~') return Key{ .movement = .home_key };
                        },
                        '3' => {
                            const c3 = readByte() catch return Key{ .char = '\x1b' };
                            if (c3 == '~') return Key.delete;
                        },
                        '4' => {
                            const c3 = readByte() catch return Key{ .char = '\x1b' };
                            if (c3 == '~') return Key{ .movement = .end_key };
                        },
                        '5' => {
                            const c3 = readByte() catch return Key{ .char = '\x1b' };
                            if (c3 == '~') return Key{ .movement = .page_up };
                        },
                        '6' => {
                            const c3 = readByte() catch return Key{ .char = '\x1b' };
                            if (c3 == '~') return Key{ .movement = .page_down };
                        },
                        else => {
                            return Key{ .char = '\x1b' };
                        },
                    }
                } else if (c1 == 'O') {
                    const c2 = readByte() catch return Key{ .char = '\x1b' };
                    switch (c2) {
                        'F' => return Key{ .movement = .end_key },
                        'H' => return Key{ .movement = .home_key },
                        else => {},
                    }
                }
            },
            ctrlKey('n') => return Key{
                .movement = .arr_down,
            },
            ctrlKey('p') => return Key{
                .movement = .arr_up,
            },
            ctrlKey('f') => return Key{
                .movement = .arr_right,
            },
            ctrlKey('b') => return Key{
                .movement = .arr_left,
            },
            else => {},
        }
        return Key{ .char = c };
    }

    fn readByte() !u8 {
        var buffer: [1]u8 = undefined;
        _ = try stdin.read(buffer[0..]);
        return buffer[0];
    }

    inline fn ctrlKey(comptime ch: u8) u8 {
        return ch & 0x1f;
    }
};
