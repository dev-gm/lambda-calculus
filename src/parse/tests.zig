const std = @import("std");
const testing = std.testing;
const assert = std.debug.assert;
const ArrayList = std.ArrayList;

const lexer = @import("./lexer.zig");
const expr = @import("./expr.zig");

const LexToken = lexer.LexToken;
const Cmd = expr.Cmd;
const Expr = expr.Expr;
const FullExpr = expr.FullExpr;

fn expectExpr(input: []const u8, expected: []const u8) !void {
    const tokens = try LexToken.parseStr(input, testing.allocator);
    defer LexToken.freeArrayList(tokens);
    var aliases = std.StringHashMap(Expr.Abstraction).init(testing.allocator);
    defer aliases.deinit();
    const full_expr = try FullExpr.parseLexTokens(tokens.items, &aliases, testing.allocator);
    defer full_expr.deinit(testing.allocator);
    var result = ArrayList(u8).init(testing.allocator);
    defer result.deinit();
    try std.fmt.formatType(full_expr, "", .{}, result.writer(), 1<<16-1);
    try testing.expectEqualStrings(result.items, expected);
}

test ".h" {
    try expectExpr(
        ".h",
        "FullExpr{ .command = Cmd{ .help = 0 } }",
    );
}

test ".q" {
    try expectExpr(
        ".q",
        "FullExpr{ .command = Cmd{ .quit = 0 } }",
    );
}

test ".r FILENAME.txt" {
    try expectExpr(
        ".r FILENAME.txt",
        "FullExpr{ .command = Cmd{ .read = { 70, 73, 76, 69, 78, 65, 77, 69, 46, 116, 120, 116 } } }"
    );
}

test ".w FILENAME.txt" {
    try expectExpr(
        ".w FILENAME.txt",
        "FullExpr{ .command = Cmd{ .write = { 70, 73, 76, 69, 78, 65, 77, 69, 46, 116, 120, 116 } } }"
    );
}

test "\\i.i" {
    try expectExpr(
        "\\i.i",
        "FullExpr{ .expression = Expr{ .abstraction = Abstraction{ .argument = 0, .expression = Expr{ .binding = 0 } } } }",
    );
}

test "\\i.i" {
    try expectExpr(
        "\\i.i",
        "FullExpr{ .expression = Expr{ .abstraction = Abstraction{ .argument = 0, .expression = Expr{ .binding = 0 } } } }",
    );
}

test "\\a.\\b.a" {
    try expectExpr(
        "\\a.\\b.a",
        "FullExpr{ .expression = Expr{ .abstraction = Abstraction{ .argument = 0, .expression = Expr{ .abstraction = Abstraction{ .argument = 1, .expression = Expr{ .binding = 0 } } } } } }",
    );
}

test "\\a.\\b.b" {
    try expectExpr(
        "\\a.\\b.b",
        "FullExpr{ .expression = Expr{ .abstraction = Abstraction{ .argument = 0, .expression = Expr{ .abstraction = Abstraction{ .argument = 1, .expression = Expr{ .binding = 1 } } } } } }",
    );
}

test "\\b.\\b.b" {
    expectExpr(
        "\\b.\\b.b",
        "FullExpr{ .expression = Expr{ .abstraction = Abstraction{ .argument = 0, .expression = Expr{ .abstraction = Abstraction{ .argument = 1, .expression = Expr{ .binding = 1 } } } } } }",
    ) catch |err| {
        try testing.expect(err == Expr.ParseError.BindingNotFound);
        return;
    };
}

test "\\\\" {
    expectExpr(
        "\\\\",
        "FullExpr{ .expression = Expr{ .abstraction = Abstraction{ .argument = 0, .expression = Expr{ .abstraction = Abstraction{ .argument = 1, .expression = Expr{ .binding = 1 } } } } } }",
    ) catch |err| {
        try testing.expect(err == Expr.ParseError.SyntaxError);
        return;
    };
}
