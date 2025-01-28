const std = @import("std");
const log = std.log;
const fs = std.fs;
const json = std.json;

const DJSON = @import("./domain.zig").JSON;

fn register(allocator: std.mem.Allocator, instance: []const u8, data: DJSON.Register) !std.ArrayList(u8) {
    // register http POST function

    // prepare register url
    const register_url = try std.fmt.allocPrint(allocator, "{s}/register", .{instance});
    defer allocator.free(register_url);

    log.debug("register url {s}", .{register_url});

    // turn into uri
    // TODO: check if there is a way to make this also accept url's without http/https prefix!
    const register_uri = try std.Uri.parse(register_url);

    // initialize zig http client
    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();

    // prepare response body (arraylist)
    var body = std.ArrayList(u8).init(allocator);
    // defer body.deinit();

    // prepare request body
    const payload = try json.stringifyAlloc(allocator, data, .{});
    defer allocator.free(payload);
        
    // make POST request
    const res = try client.fetch(.{
        .location = .{
            .uri = register_uri,
        },
        .method = .POST,
        .payload = payload,
        .extra_headers = &.{
            .{ .name = "content-type", .value = "application/json" }, 
            // the server always expects JSON but this looks pretty..
        },
        .response_storage = .{
            .dynamic = &body
        }
    });

    if (res.status == .ok) {
        return body; // only return body if status is successful
    } 

    defer body.deinit(); // early deinit body if status was not successful

    if (res.status == .not_found) { // 404 special case (for now)
        log.err("Error registering: {s}", .{"Not Found!"}); // log error
        return error.silent; // silently exit (error already logged)
    }
    
    const err = try json.parseFromSlice(DJSON.Error, allocator, body.items, .{}); // parse error
    defer err.deinit();

    log.err("Error registering: {s}", .{err.value.err}); // log error
    return error.silent; // silently exit (error already logged)
}

pub fn register_step(args: *std.process.ArgIterator, allocator: std.mem.Allocator, instance: []const u8) !void {
    // register branch
    if (args.next()) |filepath| { // filepath to save file
        if (args.next()) |username| { // username 
            if (args.next()) |password| { // password

                // open or create save file
                const save_file = try fs.cwd().createFile(filepath, .{}); // TODO: handle errors more gracefully
                defer save_file.close();

                // get result from http POST request to instance
                const res = try register(allocator, instance, DJSON.Register{
                    .username = username,
                    .password = password,
                });
                defer res.deinit();

                // parse token from result
                const token = try json.parseFromSlice(DJSON.Token, allocator, res.items, .{});
                defer token.deinit();

                // prepare save-data as JSON object
                const save = DJSON.SaveData {
                    .instance = instance,
                    .token = token.value.user_token,
                };

                // turn save-data into JSON string
                const save_json = try json.stringifyAlloc(allocator, save, .{});
                defer allocator.free(save_json);

                // save into file
                try save_file.writeAll(save_json);

                return;
            }
        }
    }

    log.err("Usage: ...", .{}); // TODO: add USAGE message
}