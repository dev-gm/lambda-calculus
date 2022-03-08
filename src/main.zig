const std = @import("std");
const ArrayList = std.ArrayList;
const GeneralPurposeAllocator = std.heap.GeneralPurposeAllocator;

const LexToken = union(enum) {
    group: ArrayList(LexToken),
    text: []const u8,
    lambda,
    dot,
    equals,

    pub fn parseStr(string: []const u8, allocator: anytype) !ArrayList(LexToken) {
        return (try parseSubStr(string, false, allocator)).tokens;
    }


    const subStrReturnType = struct {
        tokens: ArrayList(LexToken),
        index: usize,
    };

    fn subStrReturn(tokens: ArrayList(LexToken), index: usize) subStrReturnType {
        return subStrReturnType { .tokens = tokens, .index = index };
    }

    fn parseSubStr(string: []const u8, is_inner: bool, allocator: anytype) anyerror!subStrReturnType {
        var tokens = ArrayList(LexToken).init(allocator);
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
                        try tokens.append(LexToken{ .text = string[start_index.*..index] });
                        text_start = null;
                    }
                    switch (char) {
                        '(' => {
                            const result = try LexToken.parseSubStr(string[index+1..], true, allocator);
                            try tokens.append(LexToken{ .group = result.tokens });
                            skip_until = result.index;
                        },
                        ')' => return subStrReturn(tokens, index),
                        '\\' => try tokens.append(LexToken.lambda),
                        '.' => {
                            try tokens.append(LexToken.dot);
                            if (tokens.items.len == 1 and !is_inner) {
                                try tokens.append(LexToken{ .text = string[index+1..] });
                                return subStrReturn(tokens, index);
                            }
                        },
                        '=' => try tokens.append(LexToken.equals),
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
            try tokens.append(LexToken{ .text = string[start_index.*..] });
            text_start = null;
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
    const Variable = []const u8;

    fn newVariable(variable: Variable) Expr {
        return Expr{ .variable = variable };
    }

    const Abstraction = struct {
        variable: Variable,
        expression: *const Expr,
    };

    fn newAbstraction(variable: Variable, expression: *const Expr) Expr {
        return Expr{
            .abstraction = Abstraction{
                .variable = variable,
                .expression = expression,
            },
        };
    }

    const Application = struct {
        abstraction: *const Expr,
        argument: *const Expr,
    };

    fn newApplication(abstraction: *const Expr, argument: *const Expr) Expr {
        return Expr{
            .application = Application{
                .abstraction = abstraction,
                .argument = argument,
            },
        };
    }

    variable: Variable,
    abstraction: Abstraction,
    application: Application,

    pub fn parseTokens(tokens: []const LexToken) ExprParseError!Expr {
        if (tokens.len == 0) {
            return ExprParseError.EmptyExpr;
        }
        switch (tokens[0]) {
            LexToken.group => |*group| {
                const group_expr = try Expr.parseTokens(group.*.items);
                if (tokens.len == 1) {
                    return group_expr;
                } else {
                    return Expr.newApplication(
                        &group_expr,
                        &(try Expr.parseTokens(tokens[1..])),
                    );
                }
            },
            LexToken.text => |*text| {
                const variable_expr = Expr.newVariable(text.*);
                if (tokens.len == 1) {
                    return variable_expr;
                } else {
                    return Expr.newApplication(
                        &variable_expr,
                        &(try Expr.parseTokens(tokens[1..])),
                    );
                }
            },
            LexToken.lambda => {
                if (
                    tokens.len < 4 or
                    !std.mem.eql(u8, @tagName(tokens[1]), "text") or
                    !std.mem.eql(u8, @tagName(tokens[2]), "dot")
                ) {
                    return ExprParseError.SyntaxError;
                }
                return Expr.newAbstraction(
                    tokens[1].text,
                    &(try Expr.parseTokens(tokens[3..])),
                );
            },
            else => return ExprParseError.SyntaxError,
        }
    }
};

const CmdParseError = error{
    InvalidCommand,
};

const Cmd = union(enum) {
    quit: u0,
    help: u0,
    read: []const u8,
    write: []const u8,

    pub fn parseStr(string: []const u8) CmdParseError!Cmd {
        return switch (string[0]) {
            'q' => Cmd{ .quit = 0 },
            'h' => Cmd{ .help = 0 },
            'r', 'w' => {
                var i: usize = 1;
                const body = while (i < string.len): (i += 1) {
                    if (string[i] != ' ' and string[i] != '\t')
                        break string[i..];
                } else "";
                return switch (string[0]) {
                    'r' => Cmd{ .read = body },
                    'w' => Cmd{ .write = body },
                    else => unreachable,
                };
            },
            else => CmdParseError.InvalidCommand,
        };
    }
};

const FullExprParseError = ExprParseError || CmdParseError;

const FullExpr = union(enum) {
    const Assignment = struct {
        alias: []const u8,
        expression: Expr,
    };

    expression: Expr,
    command: Cmd,
    assignment: Assignment,
    empty,

    pub fn parseLexTokens(tokens: []const LexToken) FullExprParseError!FullExpr {
        if (tokens.len == 0) {
            return FullExpr.empty;
        } else if (std.mem.eql(u8, @tagName(tokens[0]), "dot")) {
            return FullExpr{
                .command = try Cmd.parseStr(tokens[1].text),
            };
        } else if (
            tokens.len > 2 and
            std.mem.eql(u8, @tagName(tokens[0]), "text") and
            std.mem.eql(u8, @tagName(tokens[1]), "equals")
        ) {
            return FullExpr{
                .assignment = Assignment{
                    .alias = tokens[0].text,
                    .expression = try Expr.parseTokens(tokens[2..]),
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

const HELP_STRING = "";

pub fn main() !void {
    const stdin = std.io.getStdIn();
    defer stdin.close();
    var tokens: ArrayList(LexToken) = undefined;
    var buffer: [INPUT_BUF_SIZE]u8 = undefined;
    var line: ?[]u8 = undefined;
    var reader = stdin.reader();
    std.debug.print("Lambda calculus interpreter. 'h' to get help.\n", .{});
    var general_allocator = GeneralPurposeAllocator(.{}){};
    defer _ = general_allocator.deinit();
    main: while (true) {
        std.debug.print(">", .{});
        line = reader.readUntilDelimiterOrEof(&buffer, '\n') catch |err| {
            std.debug.print("Read error: {s}\n", .{err});
            continue :main;
        };
        tokens = LexToken.parseStr(line.?, general_allocator.allocator()) catch |err| {
            std.debug.print("Lexing error: {s}\n", .{err});
            continue :main;
        };
        defer {
            for (tokens.items) |token| {
                if (std.mem.eql(u8, @tagName(token), "group"))
                    token.group.deinit();
            }
            tokens.deinit();
        }
        const full_expr = FullExpr.parseLexTokens(tokens.items) catch |err| {
            std.debug.print("Parsing error: {s}\n", .{err});
            continue :main;
        };
        switch (full_expr) {
            FullExpr.expression => |*expression| std.debug.print("{any}\n", .{expression.*}),
            FullExpr.command => |*command| {
                switch (command.*) {
                    Cmd.quit => break :main,
                    Cmd.help => std.debug.print("{s}\n", .{HELP_STRING}),
                    Cmd.read => |*read| std.debug.print("Read from {s}...\n", .{read.*}),
                    Cmd.write => |*write| std.debug.print("Write to {s}...\n", .{write.*}),
                }
            },
            FullExpr.assignment => |*assignment| std.debug.print("{any}\n", .{assignment.*}),
            else => continue :main,
        }
    }
}
