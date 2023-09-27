const mem = @import("std").mem;
const std = @import("std");

pub const Row = struct {
    src: []u8,
    render: []u8,

    pub fn appendString(self: *Row, str: []const u8, alloc: mem.Allocator) !void {
        var len = self.src.len;
        var str_len = str.len;
        self.src = try alloc.realloc(self.src[0..len], len + str_len);
        //_ = alloc.resize(self.src[0..len], len + str_len);

        mem.copy(u8, self.src[len .. len + str_len], str);
        try self.updateRow(alloc);
    }

    pub fn updateRow(self: *Row, alloc: mem.Allocator) !void {
        alloc.free(self.render);
        self.render = try alloc.dupe(u8, self.src);
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
            //            @memset(self.src[at..at + 1], char);
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
            //for (0..self.src.len) |i| {
            //    if (i == at) {self.src[i] = char;}
            //    else {
            //        self.src[i] = old_src[j];
            //        j += 1;
            //    }
            //}
        }
        try self.updateRow(alloc);
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var allocator = gpa.allocator();
    //defer _ = gpa.deinit();
    var ro = Row{ .src = "", .render = "" };
    try ro.appendString(":x", allocator);
    std.debug.print("{s}\n", .{ro.render});
    try ro.delCharAt(0, allocator);
    std.debug.print("{s}, {s}", .{ ro.render, ro.src });
}