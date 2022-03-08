const std = @import("std");
const StringHashMap = std.StringHashMap;

const parse = @import("./parse.zig");
const Expr = parse.Expr;
const Assignment = parse.FullExpr.Assignment;
const LexToken = parse.LexToken;

pub const State = struct {
    aliases: StringHashMap(Expr),

    pub fn init(allocator: anytype) State {
        _ = allocator;
        return State{ .aliases = StringHashMap(Expr).init(allocator) };
    }

    pub fn deinit(self: *State) void {
        self.aliases.deinit();
    }

    pub fn evaluateLexTokens(self: *State, tokens: *[]LexToken) void {
        _ = self;
        _ = tokens;
    }

    pub fn evaluateAssignment(self: *State, assignment: *const Assignment) !void {
        try self.aliases.put(assignment.*.alias, assignment.*.expression);
    }
};
