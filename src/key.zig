pub const Movement = enum {
    arr_left,
    arr_right,
    arr_up,
    arr_down,
    page_up,
    page_down,
    home_key,
    end_key,
};

pub const Key = union(enum) {
    char: u8,
    movement: Movement,
    delete: void,
};
