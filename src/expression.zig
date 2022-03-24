const std = @import("std");
const StringHashMap = std.StringHashMap;
const eql = std.mem.eql;

const LinkedList = @import("./linked_list.zig").LinkedList;
const LexToken = @import("./lexer.zig").LexToken;

pub const Expr = union(enum) {
    const Self = @This();

    const AllocationError = error{OutOfMemory};

    pub const ParseError = error{
        ExprStartsWithDot,
        EqualsInExpr,
        NoSuchVarOrAlias,
        AbstractionSyntaxError,
    } || AllocationError;

    pub const Application = struct {
        abstraction: *Self, // can be anything
        argument: *Self,

        pub fn betaReduce(self: *Self.Application, var_offset: usize, allocator: anytype) void {
            self.*.abstraction.betaReduceExpr(self.*.argument, var_offset, allocator);
        }

        // replace all instances of abstraction's var with argument. returns abstraction's inner expr
        fn betaReduceExpr(self: *Self, replace: *Self, var_offset: usize, allocator: anytype) void {
            defer replace.deinit(allocator);
            switch (self.*) {
                Self.variable => |*variable| {
                    if (variable.* - var_offset == 1)
                        self.* = try replace.clone(allocator).*;
                },
                Self.abstraction => |*abstraction| {
                    abstraction.*.betaReduceExpr(replace, var_offset + 1);
                },
                Self.application => |*application| {
                    application.*.abstraction.betaReduceExpr(replace, var_offset);
                    application.*.argument.betaReduceExpr(replace, var_offset);
                },
            }
        }
    };

    variable: usize, // starts at 1, increases with expr depth
    abstraction: *Self,
    application: Self.Application,

    fn initPtr(self: Self, allocator: anytype) Self.AllocationError!*Self {
        const ptr = try allocator.create(Self);
        ptr.* = self;
        return ptr;
    }

    pub fn parseTokens(
        aliases: *const StringHashMap(*const Self),
        tokens: []const LexToken,
        allocator: anytype,
    ) Self.ParseError!*Self {
        var var_names = LinkedList([]const u8).init(.{ .first_index = 1 });
        return Self.parseTokensWithVarNames(aliases, tokens, &var_names, allocator);
    }

    fn parseTokensWithVarNames(
        aliases: *const StringHashMap(*const Self),
        tokens: []const LexToken,
        var_names: *LinkedList([]const u8),
        allocator: anytype,
    ) Self.ParseError!*Self {
        const Result = struct {
            expression: *Self,
            continue_index: ?usize,
        };
        const result = try switch (tokens[0]) {
            LexToken.group => |*group| parse: {
                break :parse Result{
                    .expression =
                        try Self.parseTokensWithVarNames(
                            aliases,
                            group.*.items,
                            var_names,
                            allocator,
                        ),
                    .continue_index = 1,
                };
            },
            LexToken.text => |*text| parse: {
                const Pred = struct {
                    const Args = struct {
                        text: []const u8,
                    };

                    fn pred(value: *[]const u8, args: Args) bool {
                        return eql(u8, value.*, args.text);
                    }
                };
                if (
                    var_names.find_args(
                        Pred.Args,
                        Pred.pred,
                        Pred.Args{ .text = text.* }
                    )
                ) |value| {
                    break :parse Result{
                        .expression =
                            try Self.initPtr(Self{
                                .variable = value.index,
                            }, allocator),
                        .continue_index = 1,
                };
                } else if (aliases.get(text.*)) |abstraction| {
                    const ApplyToMatching = struct {
                        const Args = struct {
                            depth: usize,
                        };

                        pub fn matches(other: *Self) bool {
                            return eql(u8, @tagName(other.*), "variable");
                        }

                        pub fn apply(expr: *Self, args: Args) void {
                            expr.*.variable += args.depth;
                        }
                    };
                    const cloned_abstraction = try abstraction.clone(allocator);
                    cloned_abstraction.applyToMatching(
                        ApplyToMatching,
                        ApplyToMatching.Args,
                        ApplyToMatching.Args{ .depth = var_names.*.len },
                    );
                    break :parse Result{
                        .expression = 
                            try Self.initPtr(Self{
                                .abstraction = cloned_abstraction
                            }, allocator),
                        .continue_index = 1,
                    };
                } else {
                    return Self.ParseError.NoSuchVarOrAlias;
                }
            },
            LexToken.lambda => parse: {
                break :parse if (
                    tokens.len < 4 or
                    eql(u8, @tagName(tokens[1]), "text") or
                    eql(u8, @tagName(tokens[2]), "dot")
                )
                    Result{
                        .expression = expr: {
                            try var_names.push(tokens[1].text, allocator);
                            defer _ = var_names.pop(allocator);
                            break :expr try Self.initPtr(Self{
                                .abstraction = try Self.parseTokensWithVarNames(
                                    aliases,
                                    tokens[3..],
                                    var_names,
                                    allocator,
                                ),
                            }, allocator);
                        },
                        .continue_index = null,
                    }
                else
                    Self.ParseError.AbstractionSyntaxError;
            },
            LexToken.dot => Self.ParseError.ExprStartsWithDot,
            LexToken.equals => Self.ParseError.EqualsInExpr,
        };
        return
            if (
                result.continue_index != null and
                result.continue_index.? < tokens.len
            )
                Self.initPtr(Self{
                    .application = Self.Application{
                        .abstraction = result.expression,
                        .argument = try Self.parseTokensWithVarNames(
                            aliases,
                            tokens[result.continue_index.?..],
                            var_names,
                            allocator,
                        ),
                    },
                }, allocator)
            else result.expression;
    }

    fn applyToMatching(
        self: *Self,
        comptime T: type,
        comptime args_T: type,
        args: args_T,
    ) void {
        while (true) {
            if (T.matches(self))
                T.apply(self, args);
            switch (self.*) {
                Self.abstraction => |*abstraction|
                    Self.applyToMatching(abstraction.*, T, args_T, args),
                Self.application => |*application| {
                    Self.applyToMatching(
                        application.*.argument, T, args_T, args);
                    Self.applyToMatching(application.*.abstraction, T, args_T, args);
                },
                else => {},
            }
        }
    }

    const ReductionError =  error{} || Self.Abstraction.ReductionError;

    pub fn reduce(self: *Self) void {
        switch (self.*) {
            Self.abstraction => |*abstraction|
                abstraction.*.reduce(),
            Self.application => |*application|
                application.*.betaReduce(),
            else => {},
        }
    }

    pub fn clone(self: *const Self, allocator: anytype) Self.AllocationError!*Self {
        const new_expr = try allocator.create(Self);
        new_expr.* = self.*;
        switch (new_expr.*) {
            Self.abstraction => |*abstraction| {
                new_expr.* = Self{
                    .abstraction = try abstraction.*.clone(allocator),
                };
            },
            Self.application => |*application| {
                new_expr.* = Self{
                    .application = Self.Application{
                        .abstraction = try application.*.abstraction.clone(allocator),
                        .argument = try application.*.argument.clone(allocator),
                    },
                };
            },
            Self.variable => |*variable| {
                new_expr.* = Self{
                    .variable = variable.*,
                };
            }
        }
        return new_expr;
    }

    pub fn deinit(self: *const Self, allocator: anytype) void {
        defer allocator.destroy(self);
        switch (self.*) {
            Self.abstraction => |*abstraction|
                abstraction.*.deinit(allocator),
            Self.application => |*application| {
                application.*.abstraction.deinit(allocator);
                application.*.argument.deinit(allocator);
            },
            else => {},
        }
    }
};
