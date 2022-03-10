const std = @import("std");
const eql = std.mem.eql;
const ArrayList = std.ArrayList;
const StringHashMap = std.StringHashMap;

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
            if (eql(u8, @tagName(token), "group"))
                Self.freeArrayList(token.group);
        self.deinit();
    }
};

// {} => EmptyExpr
// {body: group} => PARSE($body)
// {body: group}{rest: ..} => application(PARSE($body), PARSE($rest))
// {var: text} => binding($var)
// {var: text}{rest: ..} => application($var, PARSE($rest))
// {lambda}{arg: text}{dot}{rest: ..} => abstraction($arg, PARSE($rest))
// else => SyntaxError
pub const Expr = union(enum) {
    const Self = @This();

    const ParseError = error{
        EmptyExpr,
        SyntaxError,
        BindingNotFound,
        OutOfMemory,
    };

    pub const Abstraction = struct {
        argument: usize,
        expression: *Self,

        fn newExpr(bindings: usize, expression: *Self) Self {
            return Self{
                .abstraction = Self.Abstraction{
                    .bindings = bindings,
                    .expression = expression,
                },
            };
        }

        fn evaluate(self: Abstraction, argument: *Self) Self {
            _ = self;
            _ = argument;
        }
    };

    const Application = struct {
        abstraction: *Self,
        argument: *Self,

        fn newExpr(abstraction: *Self, argument: *Self) Self {
            return Self{
                .application = Application{
                    .abstraction = abstraction,
                    .argument = argument,
                },
            };
        }
    };

    binding: usize,
    abstraction: Abstraction,
    application: Application,

    fn parseTokens(
        tokens: []const LexToken,
        aliases: *const StringHashMap(Self.Abstraction),
        allocator: anytype,
    ) Self.ParseError!Self {
        var vars = ArrayList([]const u8).init(allocator);
        defer vars.deinit();
        return Self.innerParseTokens(tokens, &vars, aliases);
    }

    fn innerParseTokens(
        tokens: []const LexToken,
        vars: *ArrayList([]const u8),
        aliases: *const StringHashMap(Self.Abstraction),
    ) Self.ParseError!Self {
        if (tokens.len == 0) {
            return Self.ParseError.EmptyExpr;
        }
        std.debug.print("innerParseTokens: vars = {any}\n", .{vars.*.items});
        switch (tokens[0]) {
            LexToken.group => |*group| {
                var group_expr = try Self.innerParseTokens(group.*.items, vars, aliases);
                if (tokens.len == 1) {
                    return group_expr;
                } else {
                    return Self.Application.newExpr(
                        &group_expr,
                        &(try Self.innerParseTokens(tokens[1..], vars, aliases)),
                    );
                }
            },
            LexToken.text => |*text| {
                const var_identifier = identifier: {
                    if (vars.items.len == 0)
                        break :identifier null;
                    var i = vars.items.len - 1;
                    while (i >= 0) : (i -= 1) {
                        if (eql(u8, vars.items[i], text.*))
                            break :identifier i;
                    }
                    break :identifier null;
                };
                if (var_identifier) |identifier| {
                    return Self{ .binding = identifier };
                } else if (aliases.get(text.*)) |abstraction| {
                    var abstraction_expr = Self{ .abstraction = abstraction };
                    const IncrementBindings = struct {
                        fn matches(self: *const Self) bool {
                            return eql(u8, @tagName(self.*), "binding");
                        }

                        fn apply(self: *Self, args: anytype) void {
                            if (self.*) |*binding| {
                                binding.* += args[0];
                            }
                        }
                    };
                    _ = abstraction_expr.applyToAllMatching(
                        IncrementBindings.matches,
                        IncrementBindings.apply,
                        .{vars.items.len},
                    );
                    if (tokens.len == 1) {
                        return abstraction_expr;
                    } else {
                        return Self.Application.newExpr(
                            &abstraction_expr,
                            &(try Self.innerParseTokens(tokens[1..], vars, aliases)),
                        );
                    }
                } else {
                    return Self.ParseError.BindingNotFound;
                }
            },
            LexToken.lambda => {
                std.debug.print("met lambda\n", .{});
                if (
                    tokens.len < 4 or
                    !eql(u8, @tagName(tokens[1]), "text") or
                    !eql(u8, @tagName(tokens[2]), "dot")
                ) {
                    return Self.ParseError.SyntaxError;
                }
                try vars.append(tokens[1].text);
                defer _ = vars.pop();
                std.debug.print("tokens[3..] = {string}\n", .{tokens[3..]});
                const abs = Self.Abstraction.newExpr(
                    vars.items.len - 1,
                    &(try Self.innerParseTokens(tokens[3..], vars, aliases)),
                );
                std.debug.print("{any}\n", .{abs});
                return abs;
            },
            else=> return Self.ParseError.SyntaxError,
        }
    }

    // returns if the function has been called at all
    fn applyToAllMatching(
        self: *Self,
        matches: fn(*const Self) bool,
        comptime apply: fn(*Self, anytype) void,
        apply_args: anytype,
    ) bool {
        if (matches(self)) {
            apply(self, apply_args);
            return true;
        }
        return switch (self.*) {
            Self.abstraction => |*abstraction|
                abstraction.*.expression.applyToAllMatching(matches, apply, apply_args),
            Self.application => |*application| (
                 application.*.abstraction.applyToMatching(matches, apply, apply_args) || 
                 application.*.argument.applyToMatching(matches, apply, apply_args)
            ),
            else => false,
        };
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
                const body = while (i < string.len) : (i += 1) {
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

    pub fn parseLexTokens(
        tokens: []const LexToken,
        aliases: *const StringHashMap(Expr.Abstraction),
        allocator: anytype,
    ) Self.ParseError!Self {
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
            const expression = try Expr.parseTokens(tokens[2..], aliases, allocator);
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
                .expression = try Expr.parseTokens(tokens, aliases, allocator),
            };
        }
    }
};

