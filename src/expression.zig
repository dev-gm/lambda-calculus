const std = @import("std");
const StringHashMap = std.StringHashMap;
const LinkedList = @import("./linked_list.zig").LinkedList;
const eql = std.mem.eql;

pub const Expr = union(enum) {
    const Self = @This();

    const AllocationError = error{OutOfMemory};

    pub const ParseError = error{
        ExprStartsWithDot,
        EqualsInExpr,
        NoSuchVarOrAlias,
    } || AllocationError;


    pub const Application = struct {
        const ReductionError = error{};

        abstraction: *Self,
        argument: *Self,

        fn betaReduce(self: *Self.Application) ReductionError!void {}
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
        aliases: *StringHashMap(*Self),
        tokens: []const LexToken,
        allocator: anytype,
    ) Self.ParseError!*Self {
        var var_names = LinkedList([]const u8).init(allocator);
        defer var_names.deinit();
        return Self.parseTokensWithVarNames(aliases, tokens, var_names);
    }

    fn parseTokensWithVarNames(
        aliases: *StringHashMap(*Self),
        tokens: []const LexToken,
        var_names: LinkedList([]const u8),
    ) Self.ParseError!*Self {
        const result = switch (tokens[0]) {
            LexToken.group => |*group| parse: {
                break :parse .{
                    Self.parseTokensWithVarNames(
                        group.*,
                        var_names,
                    ),
                    1,
                };
            },
            LexToken.text => |*text| parse: {
                const pred = struct {
                    fn pred(value: *[]const u8) bool {
                        return eql(u8, value.*, text.*);
                    }
                }.pred;
                if (var_names.find(pred)) |value| {
                    break :parse .{
                        Self.initPtr(Self{
                            .variable = value.index,
                        }),
                        1,
                };
                } else if (aliases.get(text.*)) |abstraction| {
                    const ApplyToMatching = struct {
                        const Args = struct {
                            depth: usize = var_names.len,
                        };

                        pub fn matches(other: *Self) bool {
                            return eql(u8, @tagName(other.*), "variable");
                        }

                        pub fn apply(expr: *Self, args: Args) void {
                            expr.*.variable += args.depth;
                        }
                    };
                    abstraction.applyToMatching(
                        ApplyToMatching,
                        ApplyToMatching.args,
                        .{},
                    );
                    break :parse .{
                        Self.initPtr(Self{
                            .abstraction = abstraction,
                        }),
                        1,
                    };
                } else {
                    return Self.ParseError.NoSuchVarOrAlias;
                }
            },
            LexToken.lambda => {
                if (
                    tokens.len < 4 or
                    eql(u8, @tagName(tokens[1]), "text") or
                    eql(u8, @tagName(tokens[2]), "dot")
                ) {
                    break :parse .{
                        expr: {
                            try var_names.push(tokens[1].text);
                            defer _ = var_names.pop();
                            break :expr Self.initPtr(Self{
                                .abstraction = Self.parseTokensWithVarNames(
                                    aliases,
                                    tokens[3..],
                                    var_names,
                                ),
                            });
                        },
                        null,
                    };
                }
            },
            LexToken.dot => ExprStartsWithDot,
            LexToken.equals => EqualsInExpr,
        };
        return
            if (
                result[1] != null and
                result[1].? < tokens.len
            )
                Self.initPtr(Self{
                    .application = Self.Application{
                        .abstraction = result[0],
                        .argument = Self.parseTokensWithVarNames(
                            aliases,
                            tokens[result[1].?..],
                            var_names,
                        ),
                    },
                }, allocator)
            else result[0];
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
                    Self.applyToMatching(application.*.expression, T, args_T, args);
                },
                else => {},
            }
        }
    }

    const ReductionError =  error{} || Self.Abstraction.ReductionError;

    pub fn reduce(self: *Self) ReductionError!void {
        switch (self.*) {
            Self.application => |*application|
        }
    }

    pub fn clone(self: *Self, allocator: anytype) *Self {
        const new_expr = allocator.create(Self);
        new_expr.* = self.*;
        switch (new_expr.*) {
            Self.abstraction => |*abstraction| {
                new_expr.* = Self{
                    .abstraction = abstraction.*.clone(),
                };
            },
            Self.application => |*application| {
                new_expr.* = Self{
                    .application = Self.Application{
                        .abstraction = application.*.abstraction.clone(),
                        .argument = application.*.argument.clone(),
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
};
