const std = @import("std");
const ArrayList = std.ArrayList;

fn isWhitespace(ch: u8) bool {
    return ch == ' ' or ch == '\t';
}

pub const LexToken = struct {
    const Self = @This();

    pub const ParseError = std.mem.AllocationError;

    group: ArrayList(Self),
    text: []const u8,
    lambda: u0,
    dot: u0,
    equals: u0,

    pub fn parseString(
        string: []const u8,
        allocator: anytype
    ) Self.ParseError!ArrayList(Self) {
        var tokens = ArrayList(Self).init(allocator);
        Self.parseStringIntoArrayList(&tokens, string, true);
        return tokens;
    }

    fn parseStringIntoArrayList(
        tokens: *ArrayList(Self),
        string: []const u8,
        first: bool,
    ) Self.ParseError!void {
        var text_start: ?usize = null;
        var prev_was_text = false;
        var i = 0;
        while (i < string.len) : (i += 1) {
            if (!prev_was_text) {
                if (text_start) |start| {
                    try tokens.*.append(Self{ .text = string[start..i] });
                    text_start = null;
                }
            }
            prev_was_text = false;
            switch (string[i]) {
                '(' => try tokens.*.append(Self{
                    .group = Self.parseStringIntoArrayList(tokens, string[i+1..], false)
                }),
                ')' => return,
                "\\" => try tokens.*.append(Self{ .lambda = 0 }),
                '.' => {
                    try tokens.*.append(Self{ .dot = 0 });
                    if (first and i == 0) {
                        try tokens.*.append(Self{ .text = string[1..] });
                        return;
                    }
                },
                '=' => try tokens.*.append(Self{ .equals = 0 }),
                ' ' | '\t' => continue,
                else => {
                    if (text_start == null)
                        text_start = i;
                    prev_was_text = true;
                },
            }
        }
    }

    pub fn deinit(self: *ArrayList(Self), allocator: anytype) void {
        defer self.deinit();
        for (self) |item| {
            switch (item) {
                Self.group => |*group| Self.deinit(group.*, allocator),
                Self.text => |*text| allocator.destroy(text.*),
                else => {},
            }
        }
    }
};
