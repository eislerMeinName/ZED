pub const Highlight = enum(u8) {
    number = 31,
    match = 34,
    string = 35,
    comment = 36,
    other = 37,
};

pub const To Highlight = struct{
    HL: Highlight, 
    str: []const u8,
    col: Color,
};

