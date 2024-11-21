const std = @import("std");
const Atomic = std.atomic.Value;

const BLOCK_SIZE = 64;
const MASK = BLOCK_SIZE - 1;

fn Channel(T: type) type {
    return struct {
        allocator: std.mem.Allocator,
        producer: *Block,
        p_index: Atomic(usize),
        consumer: *Block,
        c_index: Atomic(usize),

        const Block = struct {
            items: [64]T,
            next: Atomic(?*Block),

            fn init(allocator: std.mem.Allocator) !*Block {
                const ptr = try allocator.create(Block);
                ptr.* = .{
                    .items = undefined,
                    .next = Atomic(?*Block).init(null),
                };
                return ptr;
            }
        };

        const Self = @This();

        fn init(allocator: std.mem.Allocator) Self {
            const block = try Block.init(allocator);
            return .{
                .allocator = allocator,
                .producer = block,
                .p_index = Atomic(usize).init(0),
                .consumer = block,
                .c_index = Atomic(usize).init(0),
            };
        }

        fn push(channel: *Self, value: T) !void {
            const now = channel.p_index.load(.acquire);
            const now_idx = now & MASK;
            const next = now + 1;

            _ = now_idx;
            _ = next;
            _ = value;
        }
    };
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var channel = Channel(u32).init(allocator);
    defer channel.deinit();
}
