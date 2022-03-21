const std = @import("std");
const print = std.debug.print;
const eql = std.mem.eql;
const StringHashMap = std.StringHashMap;

const LexToken = @import("./lexer.zig").LexToken;

const Expr = @import("./expression.zig").Expr;
const Cmd = @import("./command.zig").Cmd;

const FullExpr = union(enum) {
    const Self = @This();

    const ParseError = Expr.ParseError || Cmd.ParseError || error{EmptyFullExpr};

    const Assignment = struct {
        alias: []const u8,
        abstraction: *Expr,
    };

    expression: *Expr,
    command: Cmd,
    assignment: Self.Assignment,

    pub fn parseTokens(
        aliases: *StringHashMap(*Self),
        tokens: []const LexToken,
        allocator: anytype,
    ) Self.ParseError!Self {
        if (
            tokens.len > 2 and
            eql(u8, @tagName(tokens[0]), "text") and
            eql(u8, @tagName(tokens[1]), "equals")
        ) {
            return Self{
                .assignment = Self.Assignment{
                    .alias = tokens[0],
                    .abstraction = Expr.parseTokens(aliases, tokens[2..], allocator),
                },
            };
        } else if (
            tokens.len == 2 and
            eql(u8, @tagName(tokens[0]), "dot") and
            eql(u8, @tagName(tokens[1]), "text")
        ) {
            return Self{
                .command = Cmd.parseString(tokens[1])
            };
        } else {
            return Self{
                .expression = Expr.parseTokens(aliases, tokens, allocator)
            };
        }
    }
};

pub fn main() anyerror!void {
    const stdin = std.io.getStdIn();
    const stdin_reader = stdin.reader();
    const gpa = std.heap.GeneralPurposeAllocator(.{});
    defer gpa.deinit();
    var allocator = gpa.allocator();
    var buffer: [1024]u8;
    while (
        try stdin_reader.readUntilDelimiterOrEof(buffer, '\n')
    ) |line| {
        const tokens = LexToken.parseString(line, allocator);
        defer LexToken.deinit(tokens);
    }
}
