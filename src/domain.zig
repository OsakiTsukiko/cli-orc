pub const JSON = struct {
    pub const SaveData = struct {
        instance: []const u8,
        token: []const u8,
    };

    pub const Error = struct {
        err: []const u8,
    };

    pub const Login = struct {
        username: []const u8,
        password: []const u8,
    };

    pub const Token = struct {
        user_token: []const u8,
    };
};