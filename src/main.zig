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
        abstraction: *const Expr,
    };

    expression: *Expr,
    command: Cmd,
    assignment: Self.Assignment,

    pub fn parseTokens(
        aliases: *const StringHashMap(*const Expr),
        tokens: []const LexToken,
        allocator: anytype,
    ) Self.ParseError!Self {
        return if (
            tokens.len > 2 and
            eql(u8, @tagName(tokens[0]), "text") and
            eql(u8, @tagName(tokens[1]), "equals")
        ) tokens: {
            break :tokens Self{
                .assignment = Self.Assignment{
                    .alias = tokens[0].text,
                    .abstraction = try Expr.parseTokens(aliases, tokens[2..], allocator),
                },
            };
        } else if (
            tokens.len == 2 and
            eql(u8, @tagName(tokens[0]), "dot") and
            eql(u8, @tagName(tokens[1]), "text")
        ) tokens: {
            break :tokens Self{
                .command = try Cmd.parseString(tokens[1].text),
            };
        } else tokens: {
            break :tokens Self{
                .expression = try Expr.parseTokens(aliases, tokens, allocator),
            };
        };
    }

    pub fn deinit(self: *const Self, allocator: anytype) void {
        switch (self.*) {
            Self.expression => |*expr| expr.*.deinit(allocator),
            Self.assignment => |*assignment| {
                assignment.*.abstraction.deinit(allocator);
            },
            else => {},
        }
    }
};

pub fn main() anyerror!void {
    const stdin = std.io.getStdIn();
    const stdin_reader = stdin.reader();
    const stdout = std.io.getStdOut();
    const stdout_writer = stdout.writer();
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    var aliases = std.StringHashMap(*const Expr).init(allocator);
    defer aliases.clearAndFree();
    var buffer: [1024]u8 = undefined;
    _ = try stdout_writer.write(">");
    while (
        try stdin_reader.readUntilDelimiterOrEof(&buffer, '\n')
    ) |line| {
        var tokens = try LexToken.parseString(line, allocator);
        defer LexToken.deinit(&tokens, allocator);
        const full_expr = try FullExpr.parseTokens(&aliases, tokens.items, allocator);
        defer full_expr.deinit(allocator);
        try std.json.stringify(full_expr, .{ .whitespace = .{} }, stdout_writer);
        _ = try stdout_writer.write(">");
    }
}
