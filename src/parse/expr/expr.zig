const std = @import("std");
const eql = std.mem.eql;
const StringHashMap = std.StringHashMap;
const ArrayList = std.ArrayList;

const LexToken = @import("../lexer.zig").LexToken;

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

    pub const ParseError = error{
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

    pub fn parseTokens(
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
            },
            Self.application => |application| {
                application.abstraction.deinit(allocator);
                application.argument.deinit(allocator);
            },
            else => {},
        }
        allocator.destroy(self);
    }
};

