pub const Color = struct {
    RED: []const u8 = "\x1b[31m",
    GREEN: []const u8 = "\x1b[32m",
    YELLOW: []const u8 = "\x1b[33m",
    BLUE: []const u8 = "\x1b[34m",
    MAGENTA: []const u8 = "\x1b[35m",
    CYAN: []const u8 = "\x1b[36m",
    WHITE: []const u8 = "\x1b[37m",
    RESET: []const u8 = "\x1b[0m",
};

pub const ControlKeys = struct {
    quitKey: []const u8 = ":q",
    pathKey: []const u8 = ":p",
    fileKey: []const u8 = ":o",
    writeQuitKey: []const u8 = ":x",
    writeKey: []const u8 = ":w",
    quickDeleteLineKey: []const u8 = "dd",
    quickMoveWriting: u8 = 'i',
};

pub const COL = Color{};

pub const Theme = struct {
    bottom: []const u8 = COL.YELLOW,
    reset: []const u8 = COL.RESET,
};
