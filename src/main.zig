const std = @import("std");
const ArrayList = std.ArrayList;
const general_allocator = std.allocator.general_allocator;

const LexToken = union(enum) {
    group: ArrayList(LexToken),
    text: []const u8,
    lambda,
    dot,
    equals,

    pub fn parseStr(string: []const u8) !ArrayList(LexToken) {
        return try parseSubStr(string)[0];
    }

    fn parseSubStr(string: []const u8) !.{ArrayList(LexToken), usize} {
        var tokens = try ArrayList(LexToken).init(general_allocator);
        var text_start: ?usize = null;
        var skip_until: ?usize = null;
        for (string) |index, char| {
            if (skip_until) |*i| {
                if (index >= i.*)
                    skip_until = null;
                continue;
            }
            switch (char) {
                '(' | ')' | '\\' | '.' | '=' => {
                    if (text_start) |*start_index| {
                        try tokens.append(LexToken{ .text = string[start_index.*..] });
                        text_start = null;
                    }
                    switch (char) {
                        '(' => {
                            const result = try LexToken.parseSubStr(string[index+1..]);
                            try tokens.append(LexToken{ .group = result[0] });
                            skip_until = result[1];
                        },
                        ')' => return tokens,
                        '\\' => try tokens.append(LexToken.lambda),
                        '.' => try tokens.append(LexToken.dot),
                        '=' => try tokens.append(LexToken.equals),
                        else => unreachable
                    }
                },
                ' ' | '\t' => continue,
                else =>
                    if (text_start == null)
                        text_start = index,
            }
        }
        return tokens;
    }
};

const 

pub fn main() void {}
