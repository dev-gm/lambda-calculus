pub const Expr = union(enum) {
    const Self = @This();

    pub const Error = error{};

    pub const Application = struct {
        abstraction: *Expr,
        argument: *Expr,
    };

    variable: usize,
    abstraction: *Expr,
    application: Application,

    pub fn parseTokens(tokens: []const LexToken) Self.Error!Self {}
};
