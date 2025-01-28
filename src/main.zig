const std = @import("std");
const log = std.log;

const login_step = @import("./login.zig").login_step;

pub fn main_step(args: *std.process.ArgIterator, allocator: std.mem.Allocator) !void {
    if (args.next()) |action| {
        if (args.next()) |instance| {
            // const uri = try std.Uri.parse(instance);

            if (std.mem.eql(u8, action, "l") or std.mem.eql(u8, action, "login")) {
                try login_step(args, allocator, instance);
                return;
            } else if (std.mem.eql(u8, action, "r") or std.mem.eql(u8, action, "register")) {
                return;
            }
        }
    }
    
    log.err("Usage: ...", .{});
}

pub fn main() !void {
    // Initialize Allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{
        .thread_safe = true
    }){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    log.info("🔱 Hello Cli Orc!", .{});

    var args = std.process.args();

    _ = args.next(); // path

    main_step(&args, allocator) catch |err| {
        switch (err) {
            error.silent => {
                return;
            },
            else => {
                return err;
            }
        }
    };
}