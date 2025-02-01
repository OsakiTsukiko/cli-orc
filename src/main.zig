const std = @import("std");
const log = std.log;
const fs = std.fs;
const mem = std.mem;

const login_step = @import("./login.zig").login_step;
const register_step = @import("./register.zig").register_step;
const receive_step = @import("./receive.zig").receive_step;
const show_step = @import("./show.zig").show_step;
const send_step = @import("./send.zig").send_step;

const Utils = @import("./utils.zig").Utils;

pub fn main_step(args: *std.process.ArgIterator, allocator: std.mem.Allocator) !void { 
    // choose main action
    if (args.next()) |savefile_path| {

        if (args.next()) |action| {
            if (mem.eql(u8, action, "rcv") or mem.eql(u8, action, "receive")) {
                const save_file = try fs.cwd().openFile(savefile_path, .{ .mode = .read_write }); // TODO: handle errors more gracefully
                // open for read and write
                defer save_file.close();

                try receive_step(args, allocator, save_file);
                return;
            } else if (mem.eql(u8, action, "sw") or mem.eql(u8, action, "show")) {
                const save_file = try fs.cwd().openFile(savefile_path, .{ .mode = .read_only }); // TODO: handle errors more gracefully
                // open for read
                defer save_file.close();

                try show_step(args, allocator, save_file);
                return;
            } else if (mem.eql(u8, action, "s") or mem.eql(u8, action, "send")) {
                const save_file = try fs.cwd().openFile(savefile_path, .{ .mode = .read_write }); // TODO: handle errors more gracefully
                // open for read and write
                defer save_file.close();

                try send_step(args, allocator, save_file);
                return;
            } else {
                // open or create save file
                const save_file = try fs.cwd().createFile(savefile_path, .{}); // TODO: handle errors more gracefully
                // open for write
                defer save_file.close();

                if (args.next()) |raw_instance| {
                    // for login and register get the instance

                    var buff: [1024]u8 = undefined; // create buffer for prefixed url
                    var instance: []const u8 = raw_instance; // set instance to raw instance 

                    if (!mem.startsWith(u8, instance, "http://") and !std.mem.startsWith(u8, instance, "https://")) {
                        // if instance is not prefixed with http:// pr https:// 
                        instance = try std.fmt.bufPrint(&buff, "http://{s}", .{instance});
                    }

                    if (mem.eql(u8, action, "l") or std.mem.eql(u8, action, "login")) { // branch login
                        try login_step(args, allocator, instance, save_file);
                        return;
                    } else if (mem.eql(u8, action, "reg") or std.mem.eql(u8, action, "register")) { // branch register
                        try register_step(args, allocator, instance, save_file);
                        return;
                    }
                }
            }
        }
    }
    
    log.err("Usage: " ++ Utils.USAGE_GENERAL, .{});
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