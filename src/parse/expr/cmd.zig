const std = @import("std");

pub const Cmd = union(enum) {
    const Self = @This();

    pub const ParseError = error{
        InvalidCommand,
    };

    quit: u0,
    help: u0,
    read: []const u8,
    write: []const u8,

    pub fn parseStr(string: []const u8) Self.ParseError!Self {
        return switch (string[0]) {
            'q' => Self{ .quit = 0 },
            'h' => Self{ .help = 0 },
            'r', 'w' => {
                var i: usize = 1;
                const body = while (i < string.len) : (i += 1) {
                    if (string[i] != ' ' and string[i] != '\t')
                        break string[i..];
                } else "";
                return switch (string[0]) {
                    'r' => Self{ .read = body },
                    'w' => Self{ .write = body },
                    else => unreachable,
                };
            },
            else => Self.ParseError.InvalidCommand,
        };
    }
};

