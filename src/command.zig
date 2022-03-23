pub const Cmd = union(enum) {
    const Self = @This();

    pub const ParseError = error{
        EmptyCommand,
        InvalidCommand,
        NoReadOrWriteValue,
    };

    quit: u0,
    help: u0,
    read: []const u8,
    write: []const u8,

    pub fn parseString(string: []const u8) Self.ParseError!Self {
        if (string.len == 0)
            return Self.ParseError.EmptyCommand;
        return switch (string[0]) {
            'q' => Self{ .quit = 0 },
            'h' => Self{ .help = 0 },
            'r', 'w' => parse: {
                if (string.len == 1)
                    break :parse Self.ParseError.NoReadOrWriteValue;
                const body = for (string[1..]) |char, index| body: {
                    if (char != ' ' and char != '\t' and char != '\n')
                        break :body string[index+2..];
                };
                if (body.len == 0) {
                    break :parse Self.ParseError.NoReadOrWriteValue;
                }
                break :parse switch (string[1]) {
                    'r' => Self{ .read = body },
                    'w' => Self{ .write = body },
                    else => unreachable,
                };
            },
            else => Self.ParseError.InvalidCommand,
        };
    }
};
