const std = @import("std");
const fs = @import("std").fs;
const heap = std.heap;
var gpa = heap.GeneralPurposeAllocator(.{}){};

pub fn main() !void {
    var args = std.process.args();
    _ = args.next();

    var path = args.next() orelse "main.zig";

    var allocator = gpa.allocator();

    const file = try fs.cwd().createFile(path, .{
        .read = true,
        .truncate = false,
    });

    defer file.close();

    //read entire file
    var bytes = try file.reader().readAllAlloc(allocator, std.math.maxInt(u32));
    var lines = std.mem.split(u8, bytes, "\n");

    var linenumber: usize = 0;

    while (lines.next()) |line| {
        std.debug.print("{d}, {d}\n", .{ lines.index.?, lines.buffer.len });
        std.debug.print("{d}: {s}\n", .{ linenumber, line });
        linenumber += 1;
        //if (lines.next() == null) {
        //    return;
        //}
    }
}
