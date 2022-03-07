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
        parse: for (string) |index, char| {
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
        return tokens;
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
                var start_index = for (string[1..]) |index, char| {
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

pub fn main() void {}
