const std = @import("std");
const os = std.os;
const linux = os.linux;
const system = os.system;
const errno = system.getErrno;
const io = std.io;

const stdin_fd = io.getStdIn().handle;

const WindowSize = struct {
    rows: u16,
    cols: u16,
};

pub fn getWindowSize() !WindowSize {
    var ws: linux.winsize = undefined;
    //const fd = @as(usize, @bitCast(@as(isize, linux.STDOUT_FILENO)));
    switch (errno(system.ioctl(stdin_fd, linux.T.IOCGWINSZ, @intFromPtr(&ws)))) {
        .SUCCESS => return WindowSize{ .rows = ws.ws_row, .cols = ws.ws_col },
        //EBADF => return error.BadFileDescriptor,
        //EINVAL => return error.InvalidRequest,
        //ENOTTY => return error.NotATerminal,
        else => |err| return os.unexpectedErrno(err),
    }
    return WindowSize{ .rows = 8, .cols = 3 };
}

pub fn main() anyerror!void {
    const size: WindowSize = try getWindowSize();
    std.debug.print("Hallo, {} rows, {} cols", .{ size.rows, size.cols });
}
