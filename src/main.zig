const std = @import("std");
const GeneralPurposeAllocator = std.heap.GeneralPurposeAllocator;
const StringHashMap = std.StringHashMap;

const parse = @import("./parse.zig");

const lexer = parse.lexer;
const expr = parse.expr;

const LexToken = lexer.LexToken;
const Cmd = expr.Cmd;
const Expr = expr.Expr;
const FullExpr = expr.FullExpr;

pub inline fn println(comptime fmt: []const u8, args: anytype) void {
    std.debug.print(fmt ++ "\n", args);
}

pub inline fn printObj(object: anytype) !void {
    try std.fmt.formatType(object, "", .{}, std.io.getStdOut().writer(), 150);
    println("", .{});
}

const INPUT_BUF_SIZE = 1024;

const HELP_STRING = "";

pub fn main() !void {
    const stdin = std.io.getStdIn();
    defer stdin.close();
    var tokens: std.ArrayList(LexToken) = undefined;
    var buffer: [INPUT_BUF_SIZE]u8 = undefined;
    var line: ?[]u8 = undefined;
    var reader = stdin.reader();
    println("Lambda calculus interpreter. 'h' to get help.", .{});
    var general_allocator = GeneralPurposeAllocator(.{}){};
    defer _ = general_allocator.deinit();
    var aliases = StringHashMap(Expr.Abstraction).init(general_allocator.allocator());
    defer aliases.deinit();
    main: while (true) {
        std.debug.print(">", .{});
        line = reader.readUntilDelimiterOrEof(&buffer, '\n') catch |err| {
            println("Read error: {s}", .{err});
            continue :main;
        };
        const allocator = general_allocator.allocator();
        tokens = LexToken.parseStr(line.?, allocator) catch |err| {
            println("Lexing error: {s}", .{err});
            continue :main;
        };
        defer LexToken.freeArrayList(tokens);
        const full_expr = FullExpr.parseLexTokens(
            tokens.items,
            &aliases,
            allocator,
        ) catch |err| {
            println("Parsing error: {s}", .{err});
            continue :main;
        };
        defer full_expr.deinit(allocator);
        switch (full_expr) {
            FullExpr.expression => |*expression| try printObj(expression.*),
            FullExpr.command => |*command| {
                switch (command.*) {
                    Cmd.quit => break :main,
                    Cmd.help => println("{s}", .{HELP_STRING}),
                    Cmd.read => |*read| println("Read from {s}...", .{read.*}),
                    Cmd.write => |*write| println("Write to {s}...", .{write.*}),
                }
            },
            FullExpr.assignment => |*assignment| {
                aliases.putNoClobber(
                    assignment.*.alias,
                    assignment.*.expression.abstraction,
                ) catch |err| {
                    println("Creating alias error: {s}", .{err});
                    continue :main;
                };
            },
            else => continue :main,
        }
    }
}
