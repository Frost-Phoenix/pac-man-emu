const std = @import("std");

const rl = @import("raylib");
const Z80 = @import("zig80");

pub fn main() anyerror!void {
    const screenWidth = 800;
    const screenHeight = 450;

    rl.initWindow(screenWidth, screenHeight, "pac-man");
    defer rl.closeWindow();

    rl.setTargetFPS(60);

    while (!rl.windowShouldClose()) {
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(.light_gray);

        rl.drawText("pac-man soon :D", 315, 215, 20, .dark_gray);
    }
}
