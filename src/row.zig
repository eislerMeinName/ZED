const mem = @import("std").mem;
const std = @import("std");
const Highlight = @import("config.zig").Highlight;
const KEYWORDS = @import("config.zig").KEYWORDS;

const HIGHAT = struct {
    at: usize,
    high: Highlight,
};

pub const Row = struct {
    src: []u8,
    render: []u8,
    // offset: i16 = 0,

    pub fn appendString(self: *Row, str: []const u8, alloc: mem.Allocator) !void {
        var len = self.src.len;
        var str_len = str.len;

        //_ = alloc.resize(self.src[0..len], len + str_len);
        self.src = try alloc.realloc(self.src[0..len], len + str_len);
        // _ = alloc.resize(self.src[0..len], len + str_len);

        mem.copy(u8, self.src[len .. len + str_len], str);
        try self.updateRow(alloc);
    }

    pub fn updateRow(self: *Row, alloc: mem.Allocator) !void {
        alloc.free(self.render);
        self.render = try alloc.dupe(u8, self.src);
        try self.highlight(alloc);
    }

    pub fn delCharAt(self: *Row, at: usize, alloc: mem.Allocator) !void {
        if (at > self.src.len) return;
        mem.copy(u8, self.src[at..self.src.len], self.src[at + 1 .. self.src.len]);
        self.src.len -= 1;
        try self.updateRow(alloc);
    }

    pub fn insertCharAt(self: *Row, at: usize, alloc: mem.Allocator, char: u8) !void {
        var old_src = try alloc.dupe(u8, self.src);
        self.src = try alloc.realloc(self.src, old_src.len + 1);

        if (at > self.src.len) {
            @memset(self.src[at .. at + 1], char);
        } else {
            var j: usize = 0;
            var i: usize = 0;
            while (i < self.src.len) : (i += 1) {
                if (i == at) {
                    self.src[i] = char;
                } else {
                    self.src[i] = old_src[j];
                    j += 1;
                }
            }
        }
        try self.updateRow(alloc);
    }

    pub fn calcOffset(self: *Row, at: usize) i16 {
        var off: i16 = 0;
        for (self.src[0..at]) |c| {
            if (c == 195) off -= 1;
            if (c == 9) off += 7;
        }
        return off;
    }

    fn insertHL(self: *Row, hl: Highlight, alloc: mem.Allocator) !void {
        var index = mem.indexOf(u8, self.render, hl.str) orelse return;
        var old_render = try alloc.dupe(u8, self.render);

        while (true) {
            var endlen: usize = undefined;

            if (hl.HL == .comment) {
                endlen = old_render.len + hl.col.len;
            } else {
                endlen = index + hl.col.len + hl.str.len;
            }
            try self.insertColor(hl.col, index, endlen, alloc);

            old_render = try alloc.dupe(u8, self.render[endlen + "\x1b[0m".len .. self.render.len]);
            std.debug.print("{s}\n", .{old_render});
            var ini = mem.indexOf(u8, old_render, hl.str) orelse return;
            index = endlen + "\x1b[0m".len + ini;

            if (hl.HL != .comment) {
                const index2 = mem.indexOf(u8, self.render, KEYWORDS[0].col) orelse index;
                if (index > index2) return;
            }
        }
    }

    fn insertColor(self: *Row, col: []const u8, at: usize, end: usize, alloc: mem.Allocator) !void {
        const stop = "\x1b[0m";

        var i: usize = 0;
        for (col) |c| {
            try self.insertCharRen(at + i, c, alloc);
            i += 1;
        }

        i = 0;
        for (stop) |c| {
            try self.insertCharRen(end + i, c, alloc);
            i += 1;
        }
    }

    fn highlight(self: *Row, alloc: mem.Allocator) !void {
        var indicees = std.ArrayList(HIGHAT).init(alloc);
        defer indicees.deinit();

        for (KEYWORDS) |word| {
            var indi = try self.getIndi(alloc, word.str);
            defer indi.deinit();
            //std.debug.print("{d}\n", .{indi.items});
            for (0..indi.items.len) |_| {
                const index = indi.orderedRemove(0);
                try indicees.append(HIGHAT{ .at = index, .high = word });
            }
            //std.debug.print("{s}", .{indi.items});
            //try self.insertHL(word, alloc);
        }

        var delete = std.ArrayList(usize).init(alloc);
        defer delete.deinit();

        for (0..indicees.items.len) |h| {
            const indexComment = &indicees.items[h];

            if (indexComment.high.HL == .comment) {
                for (0..indicees.items.len) |i| {
                    const indexCompare = &indicees.items[i];

                    if (indexCompare.at > indexComment.at) try delete.append(i);
                }
            }
        }

        var minus: usize = 0;
        for (delete.items) |delat| {
            _ = indicees.orderedRemove(delat - minus);
            minus += 1;
        }

        var off: usize = 0;
        for (0..self.src.len) |i| {
            for (0..indicees.items.len) |j| {
                const index2 = &indicees.items[j];
                if (index2.at == i) {
                    switch (index2.high.HL) {
                        .number, .other => {
                            const endlen = index2.at + off + index2.high.col.len + index2.high.str.len;
                            //std.debug.print("at: {d}\n", .{index2.at});
                            try self.insertColor(index2.high.col, index2.at + off, endlen, alloc);
                            off += index2.high.col.len + "\x1b[0m".len;
                        },
                        .comment => {
                            const endlen = self.render.len + index2.high.col.len;
                            try self.insertColor(index2.high.col, index2.at + off, endlen, alloc);
                            off += index2.high.col.len;
                        },
                        else => {},
                    }
                }
            }
        }
    }

    fn getIndi(self: *Row, alloc: mem.Allocator, str: []const u8) !std.ArrayList(usize) {
        var list = std.ArrayList(usize).init(alloc);
        //defer list.deinit();

        var old_src = try alloc.dupe(u8, self.src);

        while (true) {
            var index = mem.indexOf(u8, old_src, str) orelse break;
            try list.append(index);

            for (0..str.len) |i| {
                old_src[index + i] = ' ';
            }
        }
        //std.debug.print("{d}\n", .{list.items});
        return list;
    }

    fn insertCharRen(self: *Row, at: usize, char: u8, alloc: mem.Allocator) !void {
        var old_ren = try alloc.dupe(u8, self.render);
        self.render = try alloc.realloc(self.render, old_ren.len + 1);

        if (at > self.render.len) {
            @memset(self.render[at .. at + 1], char);
        } else {
            var j: usize = 0;
            var i: usize = 0;
            while (i < self.render.len) : (i += 1) {
                if (i == at) {
                    self.render[i] = char;
                } else {
                    self.render[i] = old_ren[j];
                    j += 1;
                }
            }
        }
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var allocator = gpa.allocator();
    var ro = Row{ .src = "", .render = "" };
    try ro.appendString("a11 aa 2234//hallo1", allocator);
    //try ro.appendString("//wais1", allocator);
    //try ro.insertColor(KEYWORDS[0].col, 1, 11, allocator);
    std.debug.print("{s}\n{d}\n", .{ ro.render, ro.render.len });
    //try ro.delCharAt(0, allocator);
    //std.debug.print("{s}, {s}", .{ ro.render, ro.src });
    //try ro.insertHL(KEYWORDS[0], allocator);
    //try ro.highlight(allocator);
    //std.debug.print("{s} {d}\n", .{ ro.render, ro.render.len });
    //for (ro.render) |c| {
    //    std.debug.print("{c}", .{c});
    //}
}
