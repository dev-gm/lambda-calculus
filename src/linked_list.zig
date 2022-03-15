pub fn LinkedList(comptime Value: type) type {
    return struct {
        const Self = @This();

        const Item = struct {
            next: ?*Self.Item,
            value: *Value,
            index: usize,
        };

        head: ?*Self.Item,
        allocator: anytype,

        pub fn init(allocator: anytype) Self {
            return Self{
                .head = null,
                .allocator = allocator,
            };
        }
    
        pub fn push(self: *Self, value: Value) !void {
            const value_ptr = try self.allocator.create(Value);
            value_ptr.* = value;
            self.*.head = Self.Item{
                .next = self.*.head,
                .value = value_ptr,
                .index =
                    if (self.*.head) |*item|
                        item.*.index + 1
                    else 1
            };
        }

        pub fn pop(self: *Self) ?*Value {
            if (self.*.head) |*item| {
                defer self.allocator.destroy(item);
                self.*.head = item.*.next;
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

        pub fn find(self: *Self, pred: fn(*Value) bool) ?usize {
            const iter = self.iterator();
            while (iter.next()) |next|
                if (pred(next.value))
                    return next.index;
            return null;
        }

        pub fn iterator(self: *Self) Iterator {
            return Iterator{ .current = self.*.head };
        }

        pub fn deinit(self: *Self) void {
            defer {
                self.allocator.destroy(self);
                self.allocator.deinit();
            }
            while (self.pop()) |*value|
                self.allocator.destroy(value);
        }
    };
}
