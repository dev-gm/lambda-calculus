const std = @import("std");

pub fn LinkedList(comptime Value: type) type {
    return struct {
        const Self = @This();

        const Item = struct {
            next: ?*Self.Item,
            value: *Value,
            index: usize,
        };

        head: ?*Self.Item,
        len: usize = 1,
        first_index: usize,

        const InitOptions = struct {
            first_index: usize = 0,
        };

        pub fn init(options: InitOptions) Self {
            return Self{
                .head = null,
                .first_index = options.first_index,
            };
        }
    
        pub fn push(self: *Self, value: Value, allocator: anytype) !void {
            const value_ptr = try allocator.create(Value);
            value_ptr.* = value;
            const head_ptr = try allocator.create(Self.Item);
            head_ptr.* = Self.Item{
                .next = self.*.head,
                .value = value_ptr,
                .index =
                    if (self.*.head) |*item|
                        item.*.index + 1
                    else 1
            };
            self.*.head = head_ptr;
            self.*.len += 1;
        }

        pub fn pop(self: *Self, allocator: anytype) ?*Value {
            if (self.*.head) |*item| {
                defer allocator.destroy(item);
                self.*.head = item.*.next;
                self.*.len -= 1;
                return item.*.value;
            }
            return null;
        }

        const Iterator = struct {
            current: ?*Self.Item,

            const ReturnValue = struct {
                value: *Value,
                index: usize
            };

            pub fn next(self: *Iterator) ?ReturnValue {
                if (self.current) |*current| {
                    self.current = current.*.next;
                    return ReturnValue{
                        .value = current.*.value,
                        .index = current.*.index,
                    };
                }
                return null;
            }
        };

        pub fn iterator(self: *Self) Iterator {
            return Iterator{ .current = self.*.head };
        }

        pub fn find_args(
            self: *Self,
            comptime Args: type,
            pred: fn(*Value, Args) bool,
            args: Args
        ) ?Iterator.ReturnValue {
            var iter = self.iterator();
            while (iter.next()) |next|
                if (pred(next.value, args))
                    return next;
            return null;
        }

        pub fn find(self: *Self, pred: fn(*Value) bool) ?Iterator.ReturnValue {
            var iter = self.iterator();
            return while (iter.next()) |next| iter: {
                if (pred(next.value))
                    break :iter next;
            } else null;
        }

        pub fn deinit(self: Self, allocator: anytype) void {
            while (self.pop(allocator)) |*value|
                allocator.destroy(value);
        }
    };
}
