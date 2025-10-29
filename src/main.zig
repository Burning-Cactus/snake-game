const std = @import("std");
const linux = std.os.linux;
const posix = std.posix;

const ArrayList = std.ArrayList;
const allocator = std.heap.page_allocator;

const stdin = std.fs.File.stdin();

const Position = struct {
    x: i32,
    y: i32,
};

var segments: ArrayList(Position) = undefined;
var ball: Position = .{ .x = 0, .y = 0 };

var direction: Position = .{ .x = 0, .y = 0 };
var score: u32 = 0;

var gameOver = false;

fn handleInput() !void {
    var buf: [32]u8 = undefined;
    const bytes = try stdin.read(&buf);
    if (bytes == 0) {
        return;
    }
    switch (buf[0]) {
        'w', 'W' => {
            direction.x = 0;
            direction.y = -1;
        },
        'a', 'A' => {
            direction.x = -1;
            direction.y = 0;
        },
        's', 'S' => {
            direction.x = 0;
            direction.y = 1;
        },
        'd', 'D' => {
            direction.x = 1;
            direction.y = 0;
        },
        else => {},
    }
}

fn collide(a: *Position, b: *Position) bool {
    return a.x == b.x and a.y == b.y;
}

var prng: std.Random.Xoshiro256 = undefined;

fn placeBall() void {
    const random = prng.random();
    ball.x = random.intRangeLessThan(i32, 0, width);
    ball.y = random.intRangeLessThan(i32, 0, height);
}

fn screenWrap(entity: *Position) void {
    if (entity.x < 0 or entity.x > width) {
        entity.x = @mod(entity.x, width);
    }
    if (entity.y < 0 or entity.y > height) {
        entity.y = @mod(entity.y, height);
    }
}

fn update() !void {
    handleInput() catch {};

    var head: *Position = &segments.items[0];
    var oX = head.x;
    var oY = head.y;
    head.x += direction.x;
    head.y += direction.y;
    screenWrap(head);

    var i: usize = 1;
    while (i < segments.items.len) : (i += 1) {
        var segment: *Position = &segments.items[i];
        var tmp = segment.x;
        segment.x = oX;
        oX = tmp;
        tmp = segment.y;
        segment.y = oY;
        oY = tmp;

        screenWrap(segment);

        if (collide(head, segment)) {
            gameOver = true;
        }
    }

    if (collide(head, &ball)) {
        placeBall();
        const end = segments.items.len - 1;
        // Copy the last segment
        try segments.append(allocator, segments.items[end]);
        score += 1;
    }
}

const width: u32 = 40;
const height: u32 = 40;

var buffer: [width * height]u8 = undefined;

fn draw() void {
    // Clear the buffer
    std.debug.print("\x1b[1;1H", .{});
    var i: usize = 0;
    while (i < width * height) : (i += 1) {
        buffer[i] = ' ';
    }

    buffer[@intCast(ball.y * width + ball.x)] = 'O';

    for (segments.items) |segment| {
        buffer[@intCast(segment.y * width + segment.x)] = '#';
    }

    printScreen(&buffer, width, height);
}

fn printScreen(buf: *[width * height]u8, w: u32, h: u32) void {
    var i: usize = 0;
    while (i < h) : (i += 1) {
        const n = i * w;
        const m = n + w;
        std.debug.print("{s}\n", .{buf[n..m]});
    }
}

var old_terminal: posix.termios = undefined;

fn setupScreen() !void {
    // Alternate screen
    std.debug.print("\x1b[?1049h\x1b[?25l\x1b[2J", .{});

    // "Uncook" the terminal
    old_terminal = try posix.tcgetattr(stdin.handle);
    var raw = old_terminal;
    raw.lflag.ECHO = false;
    raw.lflag.ICANON = false;

    // Timeout for input to return
    raw.cc[@intFromEnum(posix.system.V.TIME)] = 0;
    // Minimum character count for input
    raw.cc[@intFromEnum(posix.system.V.MIN)] = 0;

    try posix.tcsetattr(stdin.handle, .FLUSH, raw);
}

fn teardownScreen() !void {
    try posix.tcsetattr(stdin.handle, .FLUSH, old_terminal);

    std.debug.print("\x1b[?1049l\x1b[?25h", .{});
}

fn handleSigInt(signal: c_int) callconv(.c) void {
    teardownScreen() catch @panic("Screen teardown failed!");
    std.debug.print("Handled Interrupt signal {d}\n", .{signal});
    posix.exit(2);
}

pub fn main() !void {
    const frameRate = 15;

    // Handle keyboard interrupts
    const action = posix.Sigaction{
        .handler = .{ .handler = handleSigInt, },
        .mask = posix.sigemptyset(),
        .flags = 0,
    };
    posix.sigaction(linux.SIG.INT, &action, null);

    try setupScreen();
    defer teardownScreen() catch @panic("Screen teardown failed!");

    segments = try ArrayList(Position).initCapacity(allocator, 20);
    defer segments.deinit(allocator);

    try segments.append(allocator, .{ .x = 3, .y = 3, });
    try segments.append(allocator, .{ .x = 3, .y = 3, });
    try segments.append(allocator, .{ .x = 3, .y = 3, });

    prng = std.Random.DefaultPrng.init(blk: {
        var seed: u64 = undefined;
        try posix.getrandom(std.mem.asBytes(&seed));
        break :blk seed;
    });

    ball = .{
        .x = 20,
        .y = 15,
    };

    direction = .{
        .x = 1,
        .y = 0,
    };

    while (!gameOver) {
        const startTime: i64 = std.time.milliTimestamp();
        try update();
        draw();
        std.debug.print("Score: {d}\n", .{score});

        const frameLength: u64 = @abs(std.time.milliTimestamp() - startTime);
        const delta = 1000000000 / frameRate - frameLength;
        std.Thread.sleep(delta);
    }

    std.debug.print("GAME OVER\n", .{});
    std.debug.print("Final score: {d}\n", .{score});
    std.debug.print("Thanks for playing!\n", .{});
    std.Thread.sleep(4 * 1000000000);
}

