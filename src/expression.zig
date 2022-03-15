const std = @import("std");
const StringHashMap = std.StringHashMap;
const LinkedList = @import("./linked_list.zig").LinkedList;

pub const Expr = union(enum) {
    const Self = @This();

    const AllocationError = error{OutOfMemory};

    pub const ParseError = error{
        ExprStartsWithDot,
        EqualsInExpr,
    } || AllocationError;


    pub const Application = struct {
        abstraction: *Self,
        argument: *Self,
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
        return switch (tokens[0]) {
            LexToken.group => |*group| parse: {
                const group_expr = Self.parseTokensWithVarNames(
                    group.*,
                    var_names,
                );
                if (tokens.len == 1) {
                    break :parse group_expr;
                } else {
                    break :parse Self.initPtr(Self{
                        .application = Self.Application{
                            .abstraction = group_expr,
                            .argument = Self.parseTokensWithVarNames(
                                tokens[1..],
                                var_names,
                            ),
                        },
                    }, allocator);
                }
            },
            LexToken.text => |*text| parse: {
                const pred = struct {
                    fn pred(value: *[]const u8) bool {
                        return std.mem.eql(u8, value.*, text.*);
                    }
                }.pred;
                if (var_names.find(pred)) |value| {
                    break :parse Self.initPtr(Self{
                        .variable = value.index,
                    });
                } else if (aliases.get(text.*)) |expr| {}
            },
            LexToken.lambda => {},
            LexToken.dot => ExprStartsWithDot,
            LexToken.equals => EqualsInExpr,
        }
    }

    pub fn applyToMatching(
        self: *Self,
        comptime T: type,
        args: anytype,
    ) void {
        current = 
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
