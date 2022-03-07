const std = @import("std");
const ArrayList = std.ArrayList;
const GeneralPurposeAllocator = std.heap.GeneralPurposeAllocator;

const LexToken = union(enum) {
    group: ArrayList(LexToken),
    text: []const u8,
    lambda,
    dot,
    equals,

    pub fn parseStr(string: []const u8) !ArrayList(LexToken) {
        return (try parseSubStr(string, false)).tokens;
    }

    const subStrReturnType: type = struct {
        tokens: ArrayList(LexToken),
        index: usize,
    };

    fn subStrReturn(tokens: ArrayList(LexToken), index: usize) subStrReturnType {
        return subStrReturnType { .tokens = tokens, .index = index };
    }

    fn parseSubStr(string: []const u8, is_inner: bool) !subStrReturnType {
        var tokens = try ArrayList(LexToken).init(GeneralPurposeAllocator({}).init());
        var text_start: ?usize = null;
        var skip_until: ?usize = null;
        parse: for (string) |char, index| {
            if (skip_until) |*i| {
                if (index >= i.*)
                    skip_until = null;
                continue :parse;
            }
            switch (char) {
                '(' | ')' | '\\' | '.' | '=' |' ' | '\t' => {
                    if (text_start) |*start_index| {
                        try tokens.append(LexToken{ .text = string[start_index.*..] });
                        text_start = null;
                    }
                    switch (char) {
                        '(' => {
                            const result = try LexToken.parseSubStr(string[index+1..], true);
                            try tokens.append(LexToken{ .group = result.tokens });
                            skip_until = result.index;
                        },
                        ')' => return subStrReturn(tokens, index),
                        '\\' => try tokens.append(LexToken.lambda),
                        '.' => {
                            try tokens.append(LexToken.dot);
                            if (tokens.len() == 0 and !is_inner) {
                                try tokens.append(LexToken{ .text = string[index+1..] });
                                return subStrReturn(tokens, index);
                            }
                        },
                        '=' => try tokens.append(LexToken.equals),
                        ' ' | '\t' => continue :parse,
                        else => unreachable
                    }
                },
                else => {
                    if (text_start == null)
                        text_start = index;
                }
            }
        }
        return subStrReturn(tokens, 0);
    }
};

// {} => EmptyExpr
// {body: group} => PARSE($body)
// {body: group}{rest: ..} => application(PARSE($body), PARSE($rest))
// {var: text} => variable($var)
// {var: text}{rest: ..} => application($var, PARSE($rest))
// {lambda}{arg: text}{dot}{rest: ..} => abstraction($arg, PARSE($rest))
// else => SyntaxError

const ExprParseError = error{
    EmptyExpr,
    SyntaxError,
};

const Expr = union(enum) {
    variable: []const u8,
    abstraction: .{[]const u8, Expr},
    application: .{Expr, Expr},

    fn parseTokens(tokens: ArrayList(LexToken)) ExprParseError!Expr {
        const tokens_len = tokens.len();
        if (tokens_len == 0) {
            return ExprParseError.EmptyExpr;
        }
        switch (tokens[0]) {
            LexToken.group => {
                const group_expr = try Expr.parseTokens(tokens[0].group);
                if (tokens_len == 1) {
                    return group_expr;
                } else {
                    return Expr{
                        .application = .{
                            group_expr,
                            try Expr.parseTokens(tokens[1..]),
                        },
                    };
                }
            },
            LexToken.text => {
                const variable_expr = Expr{ .variable = tokens[0].text };
                if (tokens_len == 1) {
                    return variable_expr;
                } else {
                    return Expr{
                        .application = .{
                            variable_expr,
                            try Expr.parseTokens(tokens[1..]),
                        },
                    };
                }
            },
            LexToken.lambda => {
                if (
                    tokens_len < 4 or
                    @tagName(tokens[1]) != "text" or
                    @tagName(tokens[2]) != "dot"
                ) {
                    return ExprParseError.SyntaxError;
                }
                return try Expr{
                    .abstraction = .{
                        tokens[1].text,
                        try Expr.parseTokens(tokens[3..]),
                    },
                };
            },
            else => return ExprParseError.SyntaxError,
        }
    }
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
                var start_index = for (string[1..]) |char, index| {
                    if (char != ' ' and char != '\t')
                        break index;
                };
                return switch (string[0]) {
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
ExprParseError ||
CmdParseError ||
error{};

const FullExpr = union(enum) {
    expression: Expr,
    command: Cmd,
    assign: .{[]const u8, Expr},
    empty,

    fn parseLexTokens(tokens: ArrayList(LexToken)) FullExprParseError!FullExpr {
        if (tokens.len() == 0) {
            return FullExpr.empty;
        } else if (@tagName(tokens[0]) == "dot") {
            return FullExpr{
                .command = try Cmd.parseStr(tokens[1].text),
            };
        } else if (
            tokens.len() > 2 and
            @tagName(tokens[0]) == "text" and
            @tagName(tokens[1]) == "equals"
        ) {
            return FullExpr{
                .assign = .{
                    tokens[0].text,
                    try Expr.parseTokens(tokens[2..]),
                },
            };
        } else {
            return FullExpr{
                .expression = try Expr.parseTokens(tokens),
            };
        }
    }
};

const INPUT_BUF_SIZE = 1024;

pub fn main() !void {
    const stdin = std.io.getStdIn();
    defer stdin.close();
    var buffer: [INPUT_BUF_SIZE]u8 = undefined;
    var line: ?[]u8 = undefined;
    var reader = stdin.reader();
    main: while (true) {
        line = reader.readUntilDelimiterOrEof(&buffer, '\n') catch continue :main;
        const tokens = try LexToken.parseStr(line.?);
        defer {
            for (tokens) |token| {
                if (@tagName(token) == "group") {
                    token.group.deinit();
                }
            }
            tokens.deinit();
        }
        const full_expr = try FullExpr.parseLexTokens(tokens);
        defer full_expr.free();
        switch (full_expr) {
            FullExpr.expression => |*expression| {
                std.debug.log("EXPRESSION", .{});
                _ = expression;
            },
            FullExpr.command => |*command| {
                switch (command.*) {
                    Cmd.quit => break :main,
                    Cmd.help => std.debug.log("HELP", .{}),
                    Cmd.read => |*read| std.debug.log("READ: {s}", .{read.*}),
                    Cmd.write => |*write| std.debug.log("READ: {s}", .{write.*}),
                }
            },
            FullExpr.assign => |*assign| {
                std.debug.log("ASSIGN {s}", .{assign.*[0]});
            },
            else => continue :main,
        }
    }
}
