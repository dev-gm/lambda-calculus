const StringHashMap = @import("std").StringHashMap;
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

    pub fn parseTokens(
        tokens: []const LexToken,
        allocator: anytype,
    ) Self.ParseError!*Self {
        var var_names = LinkedList([]const u8).init(allocator);
        defer var_names.deinit();
        return Self.parseTokensWithVarNames(tokens, var_names);
    }

    fn initPtr(self: Self, allocator: anytype) Self.AllocationError!*Self {
        const ptr = try allocator.create(Self);
        ptr.* = self;
        return ptr;
    }

    fn parseTokensWithVarNames(
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
            LexToken.text => |*text| {
                const pred = struct {}; // TODO
                // if (var_names.iter().find())
            },
            LexToken.lambda => {},
            LexToken.dot => ExprStartsWithDot,
            LexToken.equals => EqualsInExpr,
        }
    }
};
