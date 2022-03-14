const std = @import("std");
const ArrayList = std.ArrayList;

pub const LexToken = struct {
    const Self = @This();

    pub const Error = error{
        
    } || error{OutOfMemory};

    group: ArrayList(Self),
    text: []const u8,
    lambda: u0,
    period: u0,
    equals: u0,

    pub fn parseStr(string: []const u8) Self.Error!ArrayList(Self) {
        
    }
};
