const std = @import("std");
const log = std.log;

const login_step = @import("./login.zig").login_step;

pub fn main_step(args: *std.process.ArgIterator, allocator: std.mem.Allocator) !void { 
    // choose main action
    if (args.next()) |action| {
        if (args.next()) |instance| {
            // for login and register get the instance (for now URL's must be prefixed with 'http' or 'https')

            if (std.mem.eql(u8, action, "l") or std.mem.eql(u8, action, "login")) { // branch login
                try login_step(args, allocator, instance);
                return;
            } else if (std.mem.eql(u8, action, "r") or std.mem.eql(u8, action, "register")) { // branch register
                return;
            }
        }
    }
    
    log.err("Usage: ...", .{}); // TODO: add USAGE message
}

pub fn main() !void {
    // initialize allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{
        .thread_safe = true
    }){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // command line arguments
    var args = std.process.args();

    _ = args.next(); // skip path

    // run main step
    main_step(&args, allocator) catch |err| {
        switch (err) {
            error.silent => { // don't show error
                return;
            },
            else => {
                return err; // throw error
            }
        }
    };
}