const std = @import("std");
const log = std.log;
const fs = std.fs;
const json = std.json;

const DJSON = @import("./domain.zig").JSON;
const DGeneral = @import("./domain.zig").General;
const Utils = @import("./utils.zig").Utils;

fn login(allocator: std.mem.Allocator, instance: []const u8, data: DJSON.Login) !std.ArrayList(u8) {
    // login http POST function

    // prepare login url
    const login_url = try std.fmt.allocPrint(allocator, "{s}/login", .{instance});
    defer allocator.free(login_url);

    log.debug("login url {s}", .{login_url});

    // turn into uri
    // TODO: check if there is a way to make this also accept url's without http/https prefix!
    const login_uri = try std.Uri.parse(login_url);

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
            .uri = login_uri,
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
        log.err("Error logging in: {s}", .{"Not Found!"}); // log error
        return error.silent; // silently exit (error already logged)
    }
    
    const err = try json.parseFromSlice(DJSON.Error, allocator, body.items, .{}); // parse error
    defer err.deinit();

    log.err("Error logging in: {s}", .{err.value.err}); // log error
    return error.silent; // silently exit (error already logged)
}

pub fn login_step(args: *std.process.ArgIterator, allocator: std.mem.Allocator, instance: []const u8, save_file: fs.File) !void {
    // login branch
    if (args.next()) |username| { // username 
            if (args.next()) |password| { // password

            // get result from http POST request to instance
            const res = try login(allocator, instance, DJSON.Login{
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
                .chats = &[_]DGeneral.Chat{},
            };

            // turn save-data into JSON string
            const save_json = try json.stringifyAlloc(allocator, save, .{});
            defer allocator.free(save_json);

            // save into file
            try save_file.writeAll(save_json);

            return;
        }
    }

    log.err("Usage: " ++ Utils.USAGE_LOGIN, .{});
}