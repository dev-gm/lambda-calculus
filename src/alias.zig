const std = @import("std");
const eql = std.mem.eql;
const StringHashMap = std.StringHashMap;

const parse = @import("./parse.zig");
const Abstraction = parse.Expr.Abstraction;
const Assignment = parse.FullExpr.Assignment;
const LexToken = parse.LexToken;

// If {lambda}{var: text}{dot} => append $var to var_list
// If {inner: group} => eval $inner, having it temporarily add its vars on to our var_list
// If {content: text} and
//  not followed by {dot}
//  not preceeded by {lambda}
//  does not show up in var_list
//  matches alias
// => replace $content with alias
pub fn replaceAliases(aliases: *const StringHashMap(Abstraction), tokens: []LexToken, allocator: anytype) !void {
    var vars = StringHashMap(u0).init(allocator);
    defer vars.deinit();
    try innerReplaceAliases(aliases, tokens, &vars);
}

fn innerReplaceAliases(aliases: *const StringHashMap(Abstraction), tokens: []LexToken, vars: *StringHashMap(u0)) anyerror!void {
    for (tokens) |token, index| {
        switch (token) {
            LexToken.text => |*text| {
                if (
                    index > 0 and
                    index < tokens.len - 1 and
                    eql(u8, @tagName(tokens[index-1]), "lambda") and
                    eql(u8, @tagName(tokens[index+1]), "dot")
                ) {
                    try vars.*.put(text.*, 0);
                } else if (!vars.contains(text.*)) {
                    if (aliases.get(text.*)) |abstraction|
                        tokens[index] = LexToken{ .abstraction = abstraction };
                }
            },
            LexToken.group => |*group| try aliases.innerReplaceAliases(group.*.items, &(try vars.*.clone())),
            else => {},
        }
    }
}

