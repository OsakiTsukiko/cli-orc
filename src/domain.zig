pub const JSON = struct {
    pub const SaveData = struct { // save data JSON format
        instance: []const u8,
        token: []const u8,
    };

    pub const Error = struct { // seaorc error JSON format
        err: []const u8,
    };

    pub const Login = struct { // seaorc login JSON format
        username: []const u8,
        password: []const u8,
    };

    pub const Token = struct { // seaorc token response JSON format
        user_token: []const u8,
    };
};