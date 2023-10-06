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
    word: []const u8 = COL.BLUE,
    word2: []const u8 = COL.B_BLUE,
    comment: []const u8 = COL.GREY,
    number: []const u8 = COL.CYAN,
    bottom: []const u8 = COL.YELLOW,
    reset: []const u8 = COL.RESET,
};

pub const THEME = Theme{};

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

pub const KEYWORDS = [_]Highlight{
    Highlight{
        .HL = .comment,
        .str = "//",
        .col = THEME.comment,
    },

    Highlight{
        .HL = .number,
        .str = "1",
        .col = THEME.number,
    },

    Highlight{
        .HL = .number,
        .str = "2",
        .col = THEME.number,
    },

    Highlight{
        .HL = .number,
        .str = "3",
        .col = THEME.number,
    },

    Highlight{
        .HL = .number,
        .str = "4",
        .col = THEME.number,
    },

    Highlight{
        .HL = .number,
        .str = "5",
        .col = THEME.number,
    },

    Highlight{
        .HL = .number,
        .str = "6",
        .col = THEME.number,
    },

    Highlight{
        .HL = .number,
        .str = "7",
        .col = THEME.number,
    },

    Highlight{
        .HL = .number,
        .str = "8",
        .col = THEME.number,
    },

    Highlight{
        .HL = .number,
        .str = "9",
        .col = THEME.number,
    },

    Highlight{
        .HL = .other,
        .str = "const",
        .col = THEME.word,
    },

    Highlight{
        .HL = .other,
        .str = "fun",
        .col = THEME.word2,
    },

    Highlight{
        .HL = .other,
        .str = "fn",
        .col = THEME.word2,
    },

    Highlight{
        .HL = .other,
        .str = "pub",
        .col = THEME.word,
    },

    Highlight{
        .HL = .other,
        .str = "public",
        .col = THEME.word,
    },

    Highlight{
        .HL = .other,
        .str = "private",
        .col = THEME.word,
    },

    Highlight{
        .HL = .other,
        .str = "var",
        .col = THEME.word,
    },

    Highlight{
        .HL = .other,
        .str = "struct",
        .col = THEME.word2,
    },

    Highlight{
        .HL = .other,
        .str = "enum",
        .col = THEME.word2,
    },
};
