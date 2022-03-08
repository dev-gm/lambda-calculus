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

    // If {lambda}{var: text}{dot} => append $var to var_list
    // If {inner: group} => eval $inner, having it temporarily add its vars on to our var_list
    // If {content: text} and
    //  not followed by {dot}
    //  not preceeded by {lambda}
    //  does not show up in var_list
    //  matches alias
    // => replace $content with alias
    pub fn replaceAliases(self: *State, tokens: []LexToken, allocator: anytype) !void {
        var vars = StringHashMap(u0).init(allocator);
        defer vars.deinit();
        try self.innerReplaceAliases(tokens, &vars);
    }

    fn innerReplaceAliases(self: *State, tokens: []LexToken, vars: *StringHashMap(u0)) anyerror!void {
        for (tokens) |token, index| {
            switch (token) {
                LexToken.text => |*text| {
                    if (
                        index > 0 and
                        index < tokens.len - 1 and
                        std.mem.eql(u8, @tagName(tokens[index-1]), "lambda") and
                        std.mem.eql(u8, @tagName(tokens[index+1]), "dot")
                    ) {
                        try vars.*.put(text.*, 0);
                    } else if (!vars.contains(text.*)) {
                        if (self.aliases.get(text.*)) |expr|
                            tokens[index] = LexToken{ .expression = expr };
                    }
                },
                LexToken.group => |*group| try self.innerReplaceAliases(group.*.items, &(try vars.*.clone())),
                else => {},
            }
        }
    }

    pub fn evaluateAssignment(self: *State, assignment: *const Assignment) !void {
        try self.aliases.put(assignment.*.alias, assignment.*.expression);
    }
};
