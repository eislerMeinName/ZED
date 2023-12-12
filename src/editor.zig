const Key = @import("key.zig").Key;
const std = @import("std");
const io = std.io;
const os = std.os;
const fs = std.fs;
const stdin = io.getStdIn().reader();
const mem = std.mem;
const window = @import("window.zig");
const WindowSize = window.WindowSize;
const fmt = std.fmt;
const termios = os.termios;
const Row = @import("row.zig").Row;
const ArrayList = std.ArrayList;

const ControlKeys = @import("config.zig").ControlKeys;
const CK = ControlKeys{};

const Theme = @import("config.zig").Theme{};
const Color = @import("config.zig").Color{};

const zed_version = "0.1";

pub const EditorState = enum { starting, writing, controlling };

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
    cursor_offset: i16 = 0,
    shutting_down: bool,
    state: EditorState,
    control: Row,
    allocator: mem.Allocator,
    orig_termios: termios,
    file_path: []const u8,

    const Self = @This();

    pub fn init(allocator: mem.Allocator, path: []const u8) !*Editor {
        const ws = try window.getWindowSize();
        var edit = try allocator.create(Self);
        edit.* = .{
            .n_rows = ws.rows,
            .n_cols = ws.cols,
            .cursor = @Vector(2, i16){ 0, 0 },
            .rows = ArrayList(Row).init(allocator),
            .shutting_down = false,
            .control = Row{ .src = "", .render = "" },
            .allocator = allocator,
            .orig_termios = undefined,
            .file_path = "",
            .state = .controlling,
        };

        if (mem.eql(u8, path, "")) {
            edit.state = .starting;
            try edit.insertRow(0, "");
            return edit;
        }

        try edit.open(path);

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
        _ = os.linux.tcsetattr(stdin_fd, os.linux.TCSA.FLUSH, &raw);
    }

    fn disableRawMode(self: *Self) !void {
        _ = os.linux.tcsetattr(stdin_fd, os.TCSA.FLUSH, &self.orig_termios);
    }

    pub fn deinit(self: *Editor) void {
        self.disableRawMode() catch unreachable;
        for (self.rows.items) |row| {
            self.allocator.free(row.src);
            self.allocator.free(row.render);
        }
        self.allocator.free(self.control.src);
        self.allocator.free(self.control.render);
    }

    pub fn updateWindowSize(self: *Editor) !void {
        const ws = try window.getWindowSize();
        if (self.n_rows == ws.rows and self.n_cols == ws.cols) return;
        self.n_rows = ws.rows;
        self.n_cols = ws.cols;
    }

    fn open(self: *Editor, path: []const u8) !void {
        self.file_path = path;

        const file = try fs.cwd().createFile(path, .{
            .read = true,
            .truncate = false,
        });

        defer file.close();

        //read entire file
        var bytes = try file.reader().readAllAlloc(self.allocator, std.math.maxInt(u32));
        var lines = std.mem.split(u8, bytes, "\n");

        var linenumber: usize = 0;
        while (lines.next()) |line| {
            try self.insertRow(linenumber, line);
            linenumber += 1;
            if (lines.index.? == lines.buffer.len) {
                return;
            }
        }
    }

    fn save(self: *Editor) !void {
        const buffer = try self.rowsToString();
        defer self.allocator.free(buffer);

        const file = try fs.cwd().createFile(
            self.file_path,
            .{
                .read = true,
            },
        );
        defer file.close();

        try file.writeAll(buffer);
    }

    fn rowsToString(self: *Editor) ![]u8 {
        var length: usize = 0;
        for (self.rows.items) |row| {
            length += row.src.len + 1;
        }

        var buffer = try self.allocator.alloc(u8, length);

        length = 0;
        var prev_len: usize = 0;
        for (self.rows.items) |row| {
            mem.copy(u8, buffer[prev_len .. prev_len + row.src.len], row.src);
            mem.copy(u8, buffer[prev_len + row.src.len .. prev_len + row.src.len + 1], "\n");
            prev_len += row.src.len + 1;
        }

        return buffer;
    }

    fn insertNewLine(self: *Editor) !void {
        var f_row = self.row_offset + @as(usize, @intCast(self.cursor[1]));
        var f_col = self.col_offset + @as(usize, @intCast(self.cursor[0]));

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

            //var j: usize = 0;

            //for (row.src[0..f_col]) |c| {
            //    row.src[j] = c;
            //    j += 1;
            //}

            //_ = self.allocator.resize(row.src, f_col);

            row.src = try self.allocator.realloc(row.src, f_col);
            //mem.copy(u8, row.src[0.. f_col], str);
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
        var f_row = self.row_offset + @as(usize, @intCast(self.cursor[1]));
        var f_col = self.col_offset + @as(usize, @intCast(self.cursor[0]));

        if (self.rows.items.len <= f_row or (f_col == 0 and f_row == 0)) return;

        const row = &self.rows.items[f_row];

        if (f_col == 0) {
            f_col = self.rows.items[f_row - 1].src.len;
            const prev_row = &self.rows.items[f_row - 1];
            try prev_row.appendString(row.src, self.allocator);
            try self.delRow(f_row);

            if (self.cursor[1] == 0) self.row_offset -= 1 else self.cursor[1] -= 1;
            self.cursor[0] = @as(i16, @intCast(f_col));

            if (self.cursor[0] >= self.n_cols) {
                var shift: usize = self.n_cols - @as(usize, @intCast(self.cursor[0])) + 1;
                self.cursor[0] -= @as(i16, @intCast(shift));
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
        var f_row = self.row_offset + @as(usize, @intCast(self.cursor[1]));
        var f_col = self.col_offset + @as(usize, @intCast(self.cursor[0]));

        var i = self.rows.items.len;

        if (f_row >= self.rows.items.len) {
            while (i <= f_row) : (i += 1) {
                try self.insertRow(self.rows.items.len, "");
            }
        }

        const row = &self.rows.items[f_row];

        try row.insertCharAt(f_col, self.allocator, char);

        if (self.cursor[0] == self.n_cols - 1) self.col_offset += 1 else self.cursor[0] += 1;
    }

    fn processWriting(self: *Editor, input: u8) !void {
        switch (@as(Key, @enumFromInt(input))) {
            .enter => return try self.insertNewLine(),
            .arr_left, .arr_up, .arr_down, .arr_right => self.moveCursor(input),
            .esc => self.state = .controlling,
            .home => self.cursor[0] = 0,
            .del => try self.delChar(),
            else => try self.insertChar(input),
        }
    }

    fn processControlling(self: *Editor, input: u8) !void {
        switch (@as(Key, @enumFromInt(input))) {
            .esc => {
                self.state = .writing;
                try self.emptyControl();
            },
            .del => {
                if (self.control.src.len > 0) try self.control.delCharAt(self.control.src.len - 1, self.allocator);
            },
            .enter => {
                if (self.control.src.len > 1) try self.checkCommands();
            },
            .arr_left, .arr_up, .arr_down, .arr_right => self.moveCursor(input),
            else => {
                const app = [1]u8{input};
                try self.control.appendString(&app, self.allocator);
                try self.checkQuickCommands();
            },
        }
    }

    fn writeQuit(self: *Editor) !void {
        if (self.file_path.len == 0) return;
        try self.save();
        self.shutting_down = true;
    }

    fn setFilePath(self: *Editor) !void {
        const len = self.control.render.len - 3;
        var buffer = try self.allocator.alloc(u8, len);
        mem.copy(u8, buffer[0..len], self.control.render[3..self.control.render.len]);
        self.file_path = buffer;
    }

    fn QuickdeleteLine(self: *Editor) !void {
        if (self.rows.items.len == 0) return;
        var f_row = self.row_offset + @as(usize, @intCast(self.cursor[1]));
        try self.delRow(f_row);
        if (f_row >= self.rows.items.len and f_row > 0) {
            self.cursor[1] -= 1;
        }
        self.cursor[0] = 0;
    }

    fn checkQuickCommands(self: *Editor) !void {
        if (mem.eql(u8, self.control.render, CK.quickDeleteLineKey)) {
            try self.QuickdeleteLine();
        } else if (self.control.render[0] == CK.quickMoveWriting) {
            self.state = .writing;
        } else {
            return;
        }
        try self.emptyControl();
    }

    fn checkCommands(self: *Editor) !void {
        if (mem.eql(u8, self.control.render, CK.writeQuitKey)) {
            try self.writeQuit();
        } else if (mem.eql(u8, self.control.render[0..2], CK.pathKey)) {
            try self.setFilePath();
        } else if (mem.eql(u8, self.control.render[0..2], CK.fileKey)) {
            const len = self.control.render.len - 3;
            var buffer = try self.allocator.alloc(u8, len);
            mem.copy(u8, buffer[0..len], self.control.render[3..self.control.render.len]);
            try self.open(buffer);
        } else if (mem.eql(u8, self.control.render, CK.quitKey)) {
            self.shutting_down = true;
        } else if (mem.eql(u8, self.control.render, CK.writeKey)) {
            if (!(mem.eql(u8, self.file_path, ""))) try self.save();
        } else {
            std.debug.print("{d} {s}", .{ self.control.render.len, self.control.render });
            return;
        }
        try self.emptyControl();
    }

    fn emptyControl(self: *Editor) !void {
        while (self.control.src.len > 0) {
            try self.control.delCharAt(self.control.src.len - 1, self.allocator);
        }
    }

    pub fn process(self: *Editor) !void {
        const key = try self.readKey();
        switch (self.state) {
            .starting => self.state = .controlling,
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

    fn drawBottom(self: *Editor, writer: anytype) !void {
        try writer.writeAll(Theme.bottom);
        var mode = try fmt.allocPrint(self.allocator, "ZED -- mode {s} | {s} | {s}", .{ @tagName(self.state), self.file_path, self.control.src });
        defer self.allocator.free(mode);
        try writer.writeAll(mode);
        var numbers = try fmt.allocPrint(self.allocator, "{d}, {d}", .{ @as(usize, @intCast(self.cursor[1])) + self.row_offset, @as(usize, @intCast(self.cursor[0])) + self.col_offset });
        var padding = self.n_cols - mode.len - numbers.len;
        while (padding > 0) : (padding -= 1) try writer.writeAll(" ");
        try writer.writeAll(numbers);
        try writer.writeAll(Theme.reset);
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
        try writer.writeAll(Color.GREY);
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
                var len = row.src.len;
                if (len > self.n_cols) len = self.n_cols;
                try writer.writeAll(row.src[0..len]);
            }
            try writer.writeAll("\x1b[K");
            if (y < self.n_rows - 1) try writer.writeAll("\r\n");
        }
        try writer.writeAll(Color.RESET);
    }

    fn drawCentral(self: *Editor, writer: anytype, str: []const u8, len: usize) !void {
        var lPadding = @divFloor(self.n_cols - len, 2);
        while (lPadding > 0) : (lPadding -= 1) try writer.writeAll(" ");
        try writer.writeAll(str);
        try writer.writeAll("\x1b[K\r\n");
    }

    fn drawStarting(self: *Editor, writer: anytype) !void {
        var topPadding = @divFloor(self.n_rows - 1 - 6, 2);
        var floorPadding = self.n_rows - 1 - 5 - topPadding;
        while (topPadding > 0) : (topPadding -= 1) try writer.writeAll("\x1b[K\r\n");

        var version = try fmt.allocPrint(self.allocator, "ZED -- version {s}", .{zed_version});
        defer self.allocator.free(version);
        try self.drawCentral(writer, version, version.len);

        var by = "by Johannes M. Tölle";
        var byC = "by " ++ Color.RED ++ "Jo" ++ Color.GREEN ++ "ha" ++ Color.YELLOW ++ "nn" ++ Color.BLUE ++ "es " ++ Color.MAGENTA ++ "M. " ++ Color.CYAN ++ "Tö" ++ Color.RED ++ "lle";
        try self.drawCentral(writer, byC, by.len);

        try writer.writeAll(Color.RESET);

        try writer.writeAll("\x1b[K\r\n");

        var note = "Note: no file specified";
        try self.drawCentral(writer, note, note.len);

        try writer.writeAll("\x1b[K\r\n");

        var press = "Press any Key";
        try self.drawCentral(writer, press, press.len);

        while (floorPadding > 0) : (floorPadding -= 1) try writer.writeAll("\x1b[K\r\n");
    }

    pub fn refreshScreen(self: *Editor) !void {
        var buf = std.ArrayList(u8).init(self.allocator);
        defer buf.deinit();
        var writer = buf.writer();
        try writer.writeAll("\x1b[?25l");
        try writer.writeAll("\x1b[H");
        try self.drawRows(writer);

        const f_row = self.row_offset + @as(usize, @intCast(self.cursor[1]));
        const row = &self.rows.items[f_row];
        const off = row.calcOffset(@as(usize, @intCast(self.cursor[0])) + self.col_offset);
        //try writer.print("\x1b[{d};{d}H", .{ (self.cursor[1] + @as(i16, @intCast(self.row_offset))) + 1, self.cursor[0] + @as(i16, @intCast(self.col_offset)) + 1 + off });
        try writer.print("\x1b[{d};{d}H", .{ self.cursor[1] + 1, self.cursor[0] + off + 1 });
        try writer.writeAll("\x1b[?25h");
        try stdout.writeAll(buf.items);
    }

    fn moveCursor(self: *Editor, move: u8) void {
        var f_row = self.row_offset + @as(usize, @intCast(self.cursor[1]));
        var f_col = self.col_offset + @as(usize, @intCast(self.cursor[0]));

        switch (@as(Key, @enumFromInt(move))) {
            .arr_left => {
                if (self.cursor[0] == 0) {
                    if (self.col_offset > 0) {
                        self.col_offset -= 1;
                    } else {
                        if (f_row > 0) {
                            self.cursor[1] -= 1;
                            self.cursor[0] = @as(i16, @intCast(self.rows.items[f_row - 1].src.len));
                            if (@as(usize, @intCast(self.cursor[0])) > self.n_cols - 1) {
                                self.col_offset = @as(usize, @intCast(self.cursor[0])) - self.n_cols + 1;
                                self.cursor[0] = @as(i16, @intCast(self.n_cols - 1));
                            }
                        }
                    }
                } else {
                    self.cursor[0] -= 1;
                }
            },
            .arr_right => {
                if (f_row < self.rows.items.len) {
                    var row = self.rows.items[f_row];

                    if (f_col < row.src.len) {
                        if (self.cursor[0] == self.n_cols - 1) self.col_offset += 1 else self.cursor[0] += 1;
                    } else if (f_col == row.src.len and f_row + 1 < self.rows.items.len) {
                        self.cursor[0] = 0;
                        self.col_offset = 0;

                        if (self.cursor[1] == self.n_rows - 2) self.row_offset += 1 else self.cursor[1] += 1;
                    }
                }
            },
            .arr_up => {
                if (self.cursor[1] == 0) {
                    if (self.row_offset > 0) self.row_offset -= 1;
                } else {
                    self.cursor[1] -= 1;
                }
            },
            .arr_down => {
                if (f_row + 1 < self.rows.items.len) {
                    if (self.cursor[1] == self.n_rows - 2) self.row_offset += 1 else self.cursor[1] += 1;
                }
            },
            else => unreachable,
        }

        f_row = self.row_offset + @as(usize, @intCast(self.cursor[1]));
        f_col = self.col_offset + @as(usize, @intCast(self.cursor[0]));

        var length: usize = if (f_row >= self.rows.items.len) 0 else self.rows.items[f_row].src.len;

        if (f_col > length) {
            self.cursor[0] -= @as(i16, @intCast(f_col - length));

            if (self.cursor[0] < 0) {
                self.col_offset += @as(usize, @intCast(self.cursor[0]));
                self.cursor[0] = 0;
            }
        }
    }

    fn readKey(self: *Editor) !u8 {
        if (self.state == .starting) {
            _ = try readByte();
            return @intFromEnum(Key.arr_up);
        }
        const byte = try readByte();
        switch (byte) {
            @intFromEnum(Key.esc) => {
                const byte2 = readByte() catch return @intFromEnum(Key.esc);

                if (byte2 == '[') {
                    const byte3 = readByte() catch return @intFromEnum(Key.esc);
                    switch (byte3) {
                        'A' => return @intFromEnum(Key.arr_up),
                        'B' => return @intFromEnum(Key.arr_down),
                        'C' => return @intFromEnum(Key.arr_right),
                        'D' => return @intFromEnum(Key.arr_left),
                        'H' => return @intFromEnum(Key.home),
                        'F' => return @intFromEnum(Key.end),
                        '0'...'9' => {
                            const byte4 = readByte() catch return @intFromEnum(Key.esc);
                            if (byte4 == '~') {
                                switch (byte3) {
                                    '1' => return @intFromEnum(Key.home),
                                    '2' => return @intFromEnum(Key.del),
                                    '3' => return @intFromEnum(Key.end),
                                    //'4' => return @enumToInt(Key.page_up),
                                    //'5' => return @enumToInt(Key.page_down),
                                    //'6' => return @enumToInt(Key.page_down),
                                    '7' => return @intFromEnum(Key.home),
                                    '8' => return @intFromEnum(Key.end),
                                    else => {},
                                }
                            }
                        },
                        else => {},
                    }
                } else if (byte2 == 'O') {
                    const byte5 = readByte() catch return @intFromEnum(Key.esc);
                    switch (byte5) {
                        'H' => return @intFromEnum(Key.home),
                        'F' => return @intFromEnum(Key.end),
                        else => {},
                    }
                }

                return @intFromEnum(Key.esc);
            },
            else => return byte,
        }

        return byte;
    }

    fn readByte() !u8 {
        var buffer: [1]u8 = undefined;
        _ = try stdin.read(buffer[0..]);
        return buffer[0];
    }
};
