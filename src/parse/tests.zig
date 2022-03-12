const std = @import("std");
const testing = std.testing;
const assert = std.debug.assert;
const ArrayList = std.ArrayList;
const StringHashMap = std.StringHashMap;

const lexer = @import("./lexer.zig");
const expr = @import("./expr.zig");

const LexToken = lexer.LexToken;
const Cmd = expr.Cmd;
const Expr = expr.Expr;
const FullExpr = expr.FullExpr;

const TestOptions = struct {
    const Self = @This();

    aliases: StringHashMap(Expr.Abstraction) = StringHashMap(Expr.Abstraction).init(testing.allocator),

    pub fn deinit(self: *Self) void {
        self.aliases.deinit();
    }

    pub fn expectExpr(self: *TestOptions, input: []const u8, expected: []const u8) !void {
        var iter = self.aliases.iterator();
        const tokens = try LexToken.parseStr(input, testing.allocator);
        defer LexToken.freeArrayList(tokens);
        const full_expr = try FullExpr.parseLexTokens(tokens.items, &self.*.aliases, testing.allocator);
        defer full_expr.deinit(testing.allocator);
        var result = ArrayList(u8).init(testing.allocator);
        defer result.deinit();
        try std.fmt.formatType(full_expr, "", .{}, result.writer(), 1<<16-1);
        try testing.expectEqualStrings(result.items, expected);
    }
};

test ".h" {
    var options = TestOptions{};
    try options.expectExpr(
        ".h",
        "FullExpr{ .command = Cmd{ .help = 0 } }",
    );
}

test ".q" {
    var options = TestOptions{};
    defer options.deinit();
    try options.expectExpr(
        ".q",
        "FullExpr{ .command = Cmd{ .quit = 0 } }",
    );
}

test ".r FILENAME.txt" {
    var options = TestOptions{};
    defer options.deinit();
    try options.expectExpr(
        ".r FILENAME.txt",
        "FullExpr{ .command = Cmd{ .read = { 70, 73, 76, 69, 78, 65, 77, 69, 46, 116, 120, 116 } } }",
    );
}

test ".w FILENAME.txt" {
    var options = TestOptions{};
    defer options.deinit();
    try options.expectExpr(
        ".w FILENAME.txt",
        "FullExpr{ .command = Cmd{ .write = { 70, 73, 76, 69, 78, 65, 77, 69, 46, 116, 120, 116 } } }",
    );
}

test "\\i.i" {
    var options = TestOptions{};
    defer options.deinit();
    try options.expectExpr(
        "\\i.i",
        "FullExpr{ .expression = Expr{ .abstraction = Abstraction{ .argument = 0, .expression = Expr{ .binding = 0 } } } }",
    );
}

test "\\i.i" {
    var options = TestOptions{};
    defer options.deinit();
    try options.expectExpr(
        "\\i.i",
        "FullExpr{ .expression = Expr{ .abstraction = Abstraction{ .argument = 0, .expression = Expr{ .binding = 0 } } } }",
    );
}

test "\\a.\\b.a" {
    var options = TestOptions{};
    defer options.deinit();
    try options.expectExpr(
        "\\a.\\b.a",
        "FullExpr{ .expression = Expr{ .abstraction = Abstraction{ .argument = 0, .expression = Expr{ .abstraction = Abstraction{ .argument = 1, .expression = Expr{ .binding = 0 } } } } } }",
    );
}

test "\\a.\\b.b" {
    var options = TestOptions{};
    defer options.deinit();
    try options.expectExpr(
        "\\a.\\b.b",
        "FullExpr{ .expression = Expr{ .abstraction = Abstraction{ .argument = 0, .expression = Expr{ .abstraction = Abstraction{ .argument = 1, .expression = Expr{ .binding = 1 } } } } } }",
    );
}

test "\\b.\\b.b" {
    var options = TestOptions{};
    defer options.deinit();
    options.expectExpr(
        "\\b.\\b.b",
        "FullExpr{ .expression = Expr{ .abstraction = Abstraction{ .argument = 0, .expression = Expr{ .abstraction = Abstraction{ .argument = 1, .expression = Expr{ .binding = 1 } } } } } }",
    ) catch |err| {
        try testing.expect(err == Expr.ParseError.BindingNotFound);
        return;
    };
}

test "\\\\" {
    var options = TestOptions{};
    defer options.deinit();
    options.expectExpr(
        "\\\\",
        "FullExpr{ .expression = Expr{ .abstraction = Abstraction{ .argument = 0, .expression = Expr{ .abstraction = Abstraction{ .argument = 1, .expression = Expr{ .binding = 1 } } } } } }",
    ) catch |err| {
        try testing.expect(err == Expr.ParseError.SyntaxError);
        return;
    };
}

test "VAR=\\a.\\b.a & VAR" {
    var options = TestOptions{};
    defer options.deinit();
    try options.expectExpr(
        "VAR=\\a.\\b.a",
        "FullExpr{ .assignment = Assignment{ .alias = { 86, 65, 82 }, .expression = Expr{ .abstraction = Abstraction{ .argument = 0, .expression = Expr{ .abstraction = Abstraction{ .argument = 1, .expression = Expr{ .binding = 0 } } } } } } }",
    );
    try options.expectExpr(
        "VAR",
        "FullExpr{ .expression = Expr{ .abstraction = Abstraction{ .argument = 0, .expression = Expr{ .abstraction = Abstraction{ .argument = 1, .expression = Expr{ .binding = 0 } } } } } }",
    );
}

