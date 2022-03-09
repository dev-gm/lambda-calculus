const std = @import("std");
const eql = std.mem.eql;
const ArrayList = std.ArrayList;

pub const LexToken = union(enum) {
    const Self = @This();

    abstraction: Expr.Abstraction,
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
            if (eql(u8, @tagName(token), "group"))
                Self.freeArrayList(token.group);
        self.deinit();
    }
};

// {} => EmptyExpr
// {body: group} => PARSE($body)
// {body: group}{rest: ..} => application(PARSE($body), PARSE($rest))
// {var: text} => variable($var)
// {var: text}{rest: ..} => application($var, PARSE($rest))
// {lambda}{arg: text}{dot}{rest: ..} => abstraction($arg, PARSE($rest))
// else => SyntaxError

pub const Expr = union(enum) {
    const Self = @This();

    const ParseError = error{
        EmptyExpr,
        SyntaxError,
    };    

    const Variable = []const u8;

    fn newVariable(variable: Variable) Self {
        return Self{ .variable = variable };
    }

    pub const Abstraction = struct {
        variable: Variable,
        expression: *const Self,
    };

    fn newAbstraction(variable: Variable, expression: *const Self) Self {
        return Self{
            .abstraction = Abstraction{
                .variable = variable,
                .expression = expression,
            },
        };
    }

    const Application = struct {
        abstraction: *const Self,
        argument: *const Self,
    };

    fn newApplication(abstraction: *const Self, argument: *const Self) Self {
        return Self{
            .application = Application{
                .abstraction = abstraction,
                .argument = argument,
            },
        };
    }

    variable: Variable,
    abstraction: Abstraction,
    application: Application,

    fn parseTokens(tokens: []const LexToken) Self.ParseError!Self {
        if (tokens.len == 0) {
            return Self.ParseError.EmptyExpr;
        }
        switch (tokens[0]) {
            LexToken.abstraction => |*abstraction| {
                const expression = Self{
                    .abstraction = abstraction.*,
                };
                if (tokens.len == 1) {
                    return expression;
                } else {
                    return Self.newApplication(
                        &expression,
                        &(try Self.parseTokens(tokens[1..])),
                    );
                }
            },
            LexToken.group => |*group| {
                const group_expr = try Self.parseTokens(group.*.items);
                if (tokens.len == 1) {
                    return group_expr;
                } else {
                    return Self.newApplication(
                        &group_expr,
                        &(try Self.parseTokens(tokens[1..])),
                    );
                }
            },
            LexToken.text => |*text| {
                const variable_expr = Self.newVariable(text.*);
                if (tokens.len == 1) {
                    return variable_expr;
                } else {
                    return Self.newApplication(
                        &variable_expr,
                        &(try Self.parseTokens(tokens[1..])),
                    );
                }
            },
            LexToken.lambda => {
                if (
                    tokens.len < 4 or
                    !eql(u8, @tagName(tokens[1]), "text") or
                    !eql(u8, @tagName(tokens[2]), "dot")
                ) {
                    return Self.ParseError.SyntaxError;
                }
                return Self.newAbstraction(
                    tokens[1].text,
                    &(try Self.parseTokens(tokens[3..])),
                );
            },
            else => return Self.ParseError.SyntaxError,
        }
    }
};

pub const Cmd = union(enum) {
    const Self = @This();

    const ParseError = error{
        InvalidCommand,
    };

    quit: u0,
    help: u0,
    read: []const u8,
    write: []const u8,

    fn parseStr(string: []const u8) Self.ParseError!Self {
        return switch (string[0]) {
            'q' => Self{ .quit = 0 },
            'h' => Self{ .help = 0 },
            'r', 'w' => {
                var i: usize = 1;
                const body = while (i < string.len): (i += 1) {
                    if (string[i] != ' ' and string[i] != '\t')
                        break string[i..];
                } else "";
                return switch (string[0]) {
                    'r' => Self{ .read = body },
                    'w' => Self{ .write = body },
                    else => unreachable,
                };
            },
            else => Self.ParseError.InvalidCommand,
        };
    }
};

pub const FullExpr = union(enum) {
    const Self = @This();

    const ParseError = Expr.ParseError || Cmd.ParseError || Self.Assignment.ParseError;
    
    pub const Assignment = struct {
        const ParseError = error{
            ValueNotAbstraction,
        };

        alias: []const u8,
        abstraction: Expr.Abstraction,
    };

    expression: Expr,
    command: Cmd,
    assignment: Assignment,
    empty,

    pub fn parseLexTokens(tokens: []const LexToken) Self.ParseError!Self {
        if (tokens.len == 0) {
            return Self.empty;
        } else if (eql(u8, @tagName(tokens[0]), "dot")) {
            return Self{
                .command = try Cmd.parseStr(tokens[1].text),
            };
        } else if (
            tokens.len > 2 and
            eql(u8, @tagName(tokens[0]), "text") and
            eql(u8, @tagName(tokens[1]), "equals")
        ) {
            const expression = try Expr.parseTokens(tokens[2..]);
            if (eql(u8, @tagName(expression), "abstraction")) {
                return Self{
                    .assignment = Assignment{
                        .alias = tokens[0].text,
                        .abstraction = expression.abstraction,
                    },
                };
            } else {
                return Self.Assignment.ParseError.ValueNotAbstraction;
            }
        } else {
            return Self{
                .expression = try Expr.parseTokens(tokens),
            };
        }
    }
};

