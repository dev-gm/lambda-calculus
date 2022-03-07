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
                        '.' => {
                            try tokens.append(LexToken.dot);
                            if (tokens.len() == 1) {
                                try tokens.append(LexToken{ .text = string[index+1..] });
                                return tokens;
                            }
                        },
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

const Expr = union(enum) {
    variable: []const u8,
    abstraction: .{[]const u8, Expr},
    application: .{Expr, Expr},
};

const CmdParseError = error{
    InvalidCommand,
};

const Cmd = union(enum) {
    quit,
    help,
    read: []const u8,
    write: []const u8,

    fn parseStr(string: []const u8) CmdParseError!Cmd {
        return switch (string[0]) {
            'q' => Cmd.quit,
            'h' => Cmd.help,
            'r' | 'w' => {
                var start_index = for (string[1..]) |index, char| {
                    if ((char != ' ') && (char != '\t'))
                        break index;
                };
                break switch (string[0]) {
                    'r' => Cmd{ .read = string[1+start_index] },
                    'w' => Cmd{ .write = string[1+start_index] },
                    else => unreachable,
                };
            },
            else => CmdParseError.InvalidCommand,
        };
    }
};

const FullExprParseError =
CmdParseError ||
error{};

const FullExpr = union(enum) {
    expression: Expr,
    command: Cmd,
    assign: .{[]const u8, Expr},
    empty,

    fn parseLexTokens(tokens: ArrayList(LexToken)) FullExprParseError!FullExpr {
        if (tokens.len() == 0)
            return FullExpr.empty;
        if (@tagName(tokens[0]) == "dot") {
            return try Cmd.parseStr(tokens[1].text);
        }
    }
};

pub fn main() void {}
