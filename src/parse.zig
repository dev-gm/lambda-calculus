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

    const AllocationError = error{OutOfMemory};

    const ParseError = error{
        SyntaxError,
        BindingNotFound,
    } || Self.AllocationError;

    fn initPtr(self: Self, allocator: anytype) AllocationError!*Self {
        var memory = try allocator.create(Self);
        memory.* = self;
        return memory;
    }

    fn initBinding(binding: usize, allocator: anytype) AllocationError!*Self {
        return Expr.initPtr(
            Self{ .binding = binding },
            allocator,
        );
    }

    pub const Abstraction = struct {
        argument: usize,
        expression: *Self,

        fn initExpr(argument: usize, expression: *Self, allocator: anytype) AllocationError!*Self {
            return Expr.initPtr(Self{
                .abstraction = Self.Abstraction{
                    .argument = argument,
                    .expression = expression,
                },
            }, allocator);
        }
    };

    const Application = struct {
        abstraction: *Self,
        argument: *Self,

        fn initExpr(abstraction: *Self, argument: *Self, allocator: anytype) AllocationError!*Self {
            return Expr.initPtr(Self{
                .application = Application{
                    .abstraction = abstraction,
                    .argument = argument,
                },
            }, allocator);
        }
    };

    binding: usize,
    abstraction: Abstraction,
    application: Application,

    fn parseTokens(
        tokens: []const LexToken,
        aliases: *const StringHashMap(Self.Abstraction),
        allocator: anytype,
    ) Self.ParseError!*Self {
        var bindings = ArrayList([]const u8).init(allocator);
        defer bindings.deinit();
        return Self.innerParseTokens(tokens, &bindings, aliases, allocator);
    }

    fn innerParseTokens(
        tokens: []const LexToken,
        bindings: *ArrayList([]const u8),
        aliases: *const StringHashMap(Self.Abstraction),
        allocator: anytype,
    ) Self.ParseError!*Self {
        switch (tokens[0]) {
            LexToken.group => |*group| {
                const group_expr = try Self.innerParseTokens(group.*.items, bindings, aliases, allocator);
                if (tokens.len == 1) {
                    return group_expr;
                } else {
                    return Self.Application.initExpr(
                        group_expr,
                        try Self.innerParseTokens(tokens[1..], bindings, aliases, allocator),
                        allocator,
                    );
                }
            },
            LexToken.text => |*text| {
                const binding_identifier = identifier: {
                    if (bindings.items.len == 0)
                        break :identifier null;
                    var i = bindings.items.len - 1;
                    while (i >= 0) : (i -= 1) {
                        if (eql(u8, bindings.items[i], text.*))
                            break :identifier i;
                        if (i == 0)
                            break :identifier null;
                    }
                    break :identifier null;
                };
                if (binding_identifier) |identifier| {
                    return Self.initBinding(identifier, allocator);
                } else if (aliases.get(text.*)) |abstraction| {
                    const abstraction_expr = try Expr.initPtr(Self{
                        .abstraction = abstraction
                    }, allocator);
                    const IncrementBindings = struct {
                        offset: usize,

                        fn matches(self: *const Self) bool {
                            return eql(u8, @tagName(self.*), "binding");
                        }

                        fn apply(self: *const @This(), expr: *Self) void {
                            if (eql(u8, @tagName(expr.*), "binding")) {
                                expr.*.binding += self.offset;
                            }
                        }
                    };
                    _ = abstraction_expr.applyToAllMatching(
                        IncrementBindings,
                        IncrementBindings{ .offset = bindings.items.len },
                    );
                    if (tokens.len == 1) {
                        return abstraction_expr;
                    } else {
                        return Self.Application.initExpr(
                            abstraction_expr,
                            try Self.innerParseTokens(tokens[1..], bindings, aliases, allocator),
                            allocator,
                        );
                    }
                } else {
                    return Self.ParseError.BindingNotFound;
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
                try bindings.append(tokens[1].text);
                defer _ = bindings.pop();
                return Self.Abstraction.initExpr(
                    bindings.items.len - 1,
                    try Self.innerParseTokens(tokens[3..], bindings, aliases, allocator),
                    allocator
                );
            },
            else => return Self.ParseError.SyntaxError,
        }
    }

    // returns if the function has been called at all
    fn applyToAllMatching(
        self: *Self,
        comptime T: type,
        args: T,
    ) bool {
        if (T.matches(self)) {
            args.apply(self);
            return true;
        }
        return switch (self.*) {
            Self.abstraction => |*abstraction|
                abstraction.*.expression.applyToAllMatching(T, args),
            Self.application => |*application| (
                application.*.abstraction.applyToAllMatching(T, args) or
                application.*.argument.applyToAllMatching(T, args)
            ),
            else => false,
        };
    }

    pub fn deinit(self: *Self, allocator: anytype) void {
        switch (self.*) {
            Self.abstraction => |abstraction| {
                abstraction.expression.deinit(allocator);
                allocator.destroy(abstraction.expression);
            },
            Self.application => |application| {
                application.abstraction.deinit(allocator);
                allocator.destroy(application.abstraction);
                application.argument.deinit(allocator);
                allocator.destroy(application.argument);
            },
            else => {},
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
        expression: *Expr, // assume this is abstraction
    };

    expression: *Expr,
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
            if (eql(u8, @tagName(expression.*), "abstraction")) {
                return Self{
                    .assignment = Assignment{
                        .alias = tokens[0].text,
                        .expression = expression,
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

    pub fn deinit(self: Self, allocator: anytype) void {
        if (eql(u8, @tagName(self), "expression"))
            self.expression.deinit(allocator);
    }
};
