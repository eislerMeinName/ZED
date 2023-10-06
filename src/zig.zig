const Highlight = @import("config.zig").Highlight;
const Theme = @import("config.zig").Theme{};

pub const ZIGKEYS = [_]Highlight{Highlight{
    .HL = .comment,
    .str = "//",
    .col = Theme.comment,
}};
