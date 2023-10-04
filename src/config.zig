pub const Color = struct {
    RED: []const u8 = "\x1b[31m",
    GREEN: []const u8 = "\x1b[32m",
    YELLOW: []const u8 = "\x1b[33m",
    BLUE: []const u8 = "\x1b[34m",
    MAGENTA: []const u8 = "\x1b[35m",
    CYAN: []const u8 = "\x1b[36m",
    WHITE: []const u8 = "\x1b[37m",
    GREY: []const u8 = "\x1b[90m",
    B_RED: []const u8 = "\x1b[91m",
    B_GREEN: []const u8 = "\x1b[92m",
    B_YELLOW: []const u8 = "\x1b[93m",
    B_BLUE: []const u8 = "\x1b[94m",
    B_MAGENTA: []const u8 = "\x1b[95m",
    B_CYAN: []const u8 = "\x1b[96m",
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

pub const HighlightEnum = enum(u8) {
    number = 31,
    match = 34,
    string = 35,
    comment = 36,
    other = 37,
};

pub const Highlight = struct {
    HL: HighlightEnum,
    str: []const u8,
    col: []const u8,
};

pub const KEYWORDS: [10]Highlight = [10]Highlight{
    Highlight{
        .HL = .comment,
        .str = "//",
        .col = COL.GREY,
    },

    Highlight{
        .HL = .number,
        .str = "1",
        .col = COL.CYAN,
    },

    Highlight{
        .HL = .number,
        .str = "2",
        .col = COL.CYAN,
    },

    Highlight{
        .HL = .number,
        .str = "3",
        .col = COL.CYAN,
    },

    Highlight{
        .HL = .number,
        .str = "4",
        .col = COL.CYAN,
    },

    Highlight{
        .HL = .number,
        .str = "5",
        .col = COL.CYAN,
    },

    Highlight{
        .HL = .number,
        .str = "6",
        .col = COL.CYAN,
    },

    Highlight{
        .HL = .number,
        .str = "7",
        .col = COL.CYAN,
    },

    Highlight{
        .HL = .number,
        .str = "8",
        .col = COL.CYAN,
    },

    Highlight{
        .HL = .number,
        .str = "9",
        .col = COL.CYAN,
    },
};
