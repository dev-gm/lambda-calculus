const std = @import("std");
const ArrayList = std.ArrayList;

pub const LexToken = union(enum) {
    const Self = @This();

    group: ArrayList(Self),
    text: []const u8,
    lambda,
    dot,
    equals,

    pub fn parseStr(string: []const u8, allocator: anytype) !ArrayList(Self) {
        return (try parseSubStr(string, false, allocator)).tokens;
    }

    const subStrReturnType = struct {
        tokens: ArrayList(Self),
        index: usize,
    };

    fn subStrReturn(tokens: ArrayList(Self), index: usize) subStrReturnType {
        return subStrReturnType { .tokens = tokens, .index = index };
    }

    fn parseSubStr(string: []const u8, is_inner: bool, allocator: anytype) anyerror!subStrReturnType {
        var tokens = ArrayList(Self).init(allocator);
        var text_start: ?usize = null;
        var skip_until: ?usize = null;
        parse: for (string) |char, index| {
            if (skip_until) |*i| {
                if (index >= i.*)
                    skip_until = null;
                continue :parse;
            }
            switch (char) {
                '(', ')', '\\', '.', '=', ' ', '\t' => {
                    if (text_start) |*start_index| {
                        try tokens.append(Self{ .text = string[start_index.*..index] });
                        text_start = null;
                    }
                    switch (char) {
                        '(' => {
                            const result = try Self.parseSubStr(string[index+1..], true, allocator);
                            try tokens.append(Self{ .group = result.tokens });
                            skip_until = result.index;
                        },
                        ')' => return subStrReturn(tokens, index),
                        '\\' => try tokens.append(Self.lambda),
                        '.' => {
                            try tokens.append(Self.dot);
                            if (tokens.items.len == 1 and !is_inner) {
                                try tokens.append(Self{ .text = string[index+1..] });
                                return subStrReturn(tokens, index);
                            }
                        },
                        '=' => try tokens.append(Self.equals),
                        ' ', '\t' => continue :parse,
                        else => unreachable,
                    }
                },
                else => {
                    if (text_start == null)
                        text_start = index;
                }
            }
        }
        if (text_start) |*start_index| {
            try tokens.append(Self{ .text = string[start_index.*..] });
            text_start = null;
        }
        return subStrReturn(tokens, 0);
    }

    pub fn freeArrayList(self: ArrayList(Self)) void {
        for (self.items) |token|
            if (std.mem.eql(u8, @tagName(token), "group"))
                Self.freeArrayList(token.group);
        self.deinit();
    }
};

