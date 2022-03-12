const std = @import("std");
const eql = std.mem.eql;
const StringHashMap = std.StringHashMap;

const Expr = @import("./expr.zig").Expr;
const Cmd = @import("./cmd.zig").Cmd;

const LexToken = @import("../lexer.zig").LexToken;

pub const FullExpr = union(enum) {
    const Self = @This();

    pub const ParseError = Expr.ParseError || Cmd.ParseError || Self.Assignment.ParseError;
    
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
