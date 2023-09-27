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

//pub const Key = union(enum) {
//    char: u8,
//    movement: Movement,
//    delete: void,
//};

pub const Key = enum(u8) {
    tab = 9,
    enter = 13,
    esc = 27,
    arr_left,
    arr_right,
    arr_up,
    arr_down,
    del = 127,
    home,
    end,
    _,
};
