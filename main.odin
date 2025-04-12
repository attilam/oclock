package oclock

import "core:fmt"
import "core:math"
import "core:math/ease"
import "core:mem"
import "core:strings"
import "core:time"
import tz "core:time/timezone"
import dt "core:time/datetime"
import rl "vendor:raylib"

theme :: struct {
    theme, bg, marker, marker_shadow, hour, minute, second, hand_shadow, hand_highlight, day: rl.Color
}

themes := []theme {
    {
        theme = rl.RAYWHITE,
        bg = rl.RAYWHITE,
        marker = { 216, 216, 216, 255 },
        marker_shadow = { 176, 176, 176, 255 },
        hour = rl.BLACK,
        minute = rl.GRAY,
        second = rl.RED,
        hand_shadow = { 192, 192, 192, 255 },
        hand_highlight = rl.WHITE,
        day = rl.BLACK
    },
    {
        theme = rl.DARKBLUE,
        bg = rl.DARKBLUE,
        marker = rl.WHITE,
        marker_shadow = { 176, 176, 176, 255 },
        hour = rl.ORANGE,
        minute = rl.ORANGE,
        second = rl.ORANGE,
        hand_shadow = { 128, 128, 128, 255 },
        hand_highlight = rl.WHITE,
        day = rl.WHITE
    },
    {
        theme = rl.DARKPURPLE,
        bg = rl.DARKPURPLE,
        marker = rl.WHITE,
        marker_shadow = { 176, 176, 176, 255 },
        hour = rl.WHITE,
        minute = rl.WHITE,
        second = rl.WHITE,
        hand_shadow = { 192, 192, 192, 255 },
        hand_highlight = rl.WHITE,
        day = rl.WHITE
    },
    {
        theme = rl.GOLD,
        bg = rl.GOLD,
        marker = rl.RAYWHITE,
        marker_shadow = { 176, 176, 176, 255 },
        hour = rl.DARKBLUE,
        minute = rl.BLUE,
        second = rl.BLUE,
        hand_shadow = { 128, 128, 128, 255 },
        hand_highlight = { 216, 216, 255, 255 },
        day = rl.BLACK
    },
    {
        theme = { 24, 24, 32, 255},
        bg = { 24, 24, 32, 255},
        marker = { 0, 255, 216, 255 },
        marker_shadow = { 0, 176, 150, 255 },
        hour = { 0, 255, 216, 255 },
        minute = { 0, 255, 216, 255 },
        second = { 24, 24, 32, 255},
        hand_shadow = { 128, 128, 128, 255 },
        hand_highlight = { 216, 216, 255, 255 },
        day =  { 0, 255, 216, 255 }
    },
    {
        theme = rl.DARKGREEN,
        bg = rl.DARKGREEN,
        marker = rl.BLANK, //rl.ORANGE,
        marker_shadow = rl.BLANK, //{ 0, 176, 150, 255 },
        hour = rl.WHITE,
        minute = rl.WHITE,
        second = rl.ORANGE,
        hand_shadow = { 128, 128, 128, 255 },
        hand_highlight = { 216, 216, 255, 255 },
        day =  rl.WHITE
    },
}

current_theme: ^theme = &themes[0]

anim_theme: theme = theme {}
source_theme: ^theme = current_theme
anim_switch_time: i64

shadow_offset_x: f32 = 2
shadow_offset_y: f32 = 3

main :: proc() {
	when ODIN_DEBUG {
		track: mem.Tracking_Allocator
		mem.tracking_allocator_init(&track, context.allocator)
		context.allocator = mem.tracking_allocator(&track)

		defer {
			if len(track.allocation_map) > 0 {
				fmt.eprintf("=== %v allocations not freed: ===\n", len(track.allocation_map))
				for _, entry in track.allocation_map {
					fmt.eprintf("- %v bytes @ %v\n", entry.size, entry.location)
				}
			}
			if len(track.bad_free_array) > 0 {
				fmt.eprintf("=== %v incorrect frees: ===\n", len(track.bad_free_array))
				for entry in track.bad_free_array {
					fmt.eprintf("- %p @ %v\n", entry.memory, entry.location)
				}
			}
			mem.tracking_allocator_destroy(&track)
		}
	}

    rl.SetTraceLogLevel(.WARNING)

    rl.SetConfigFlags({ .WINDOW_RESIZABLE, .VSYNC_HINT, .MSAA_4X_HINT })
    rl.InitWindow(1024, 1024, "oclock")
    defer rl.CloseWindow()

    anim_switch_time = time.now()._nsec

    main_loop: for !rl.WindowShouldClose() {
        // figure out current time
        now_utc_ts := time.now()
        now_utc_dt, ok := time.time_to_datetime(now_utc_ts); assert(ok)
        local_tz, tz_ok := tz.region_load("local", allocator=context.temp_allocator) //; assert(tz_ok)
        local_dt, conv_ok := tz.datetime_to_tz(now_utc_dt, local_tz); assert(conv_ok)

        hour:= f32(local_dt.hour)
        minute := f32(local_dt.minute)
        second := f32(local_dt.second)
        nano := f32(now_utc_dt.nano) // local_dt doesn't have nanoseconds

        second_precise := second + nano / 1_000_000_000.0
        minute_precise := minute + second_precise/60.0
        hour_precise := hour + minute_precise/60.0

        second_smooth := rl.EaseElasticOut(nano/1_000_000_000.0, second-1, 1.0, 0.25) * 6

        // fmt.println(hour, minute, second)

        // setup clock face geometry
        center_x := f32(rl.GetScreenWidth() >> 1)
        center_y := f32(rl.GetScreenHeight() >> 1)

        face_size := 0.85 * f32(min(center_x, center_y))

        // update theme colors
        delta_nsec := now_utc_ts._nsec - anim_switch_time
        delta_sec := f64(delta_nsec) / 1_000_000_000.0 * 2.0

        lerp_theme(&anim_theme, source_theme, current_theme, ease.cubic_out(clamp(delta_sec, 0.0, 1.0)))

        rl.BeginDrawing()
        rl.ClearBackground(anim_theme.bg)

        // Draw minute markers
        for minutes:f32 = 0; minutes < 60; minutes += 1 {
            if i32(minutes) % 5 == 0 do continue

            draw_marker(center_x, center_y, face_size, 0.06, 0.012, minutes * 6, anim_theme.marker, 0.5, 1.5, anim_theme.marker_shadow)
        }

        // Draw hour markers
        for hours:f32 = 0; hours < 12; hours += 1 {
            l: f32 = ((i32(hours) % 3 == 0) ? 0.18 : 0.12)
            w: f32 = ((i32(hours) % 3 == 0) ? 0.030 : 0.024)

            draw_marker(center_x, center_y, face_size, l, w, hours * 30, anim_theme.marker, 0.5, 1.5, anim_theme.marker_shadow)
        }

        // Draw date
        font_size: i32= i32(face_size * 0.2)
        rl.DrawText(rl.TextFormat("%v", local_dt.date.day), i32(center_x + face_size*0.5), i32(center_y)-font_size >> 1, font_size, anim_theme.day)

        // draw hands
        draw_hand( // hour
            center_x, center_y, face_size * 0.81, face_size * 0.042,
            face_size * 0.15,
            hour_precise*30,
            face_size * 0.05,
            anim_theme.hour,
            shadow_offset_x * 0.6, shadow_offset_y * 0.6, anim_theme.hand_shadow,
            anim_theme.hand_highlight
        )
        
        draw_hand( // minute
            center_x, center_y, face_size * 1.06, face_size * 0.024,
            face_size * 0.15,
            minute_precise*6,
            face_size * 0.04,
            anim_theme.minute,
            shadow_offset_x * 0.8, shadow_offset_y * 0.8, anim_theme.hand_shadow,
            anim_theme.hand_highlight
        )

        draw_hand( // second
            center_x, center_y, face_size * 0.91, face_size * 0.018,
            0,
            second_smooth,
            face_size * 0.03,
            anim_theme.second,
            shadow_offset_x, shadow_offset_y, anim_theme.hand_shadow,
            anim_theme.hand_highlight
        )

        update_ui()

        rl.EndDrawing()

        free_all(context.temp_allocator)
    }

}

draw_marker :: proc(center_x, center_y, face_size, length, width, rotation: f32, color: rl.Color, shadow_offset_x, shadow_offset_y: f32, shadow_color: rl.Color) {
    l := face_size * length
    w := face_size * width
    pos_x := center_x + face_size*(1.0-length) * math.cos_f32(math.to_radians(rotation))
    pos_y := center_y + face_size*(1.0-length) * math.sin_f32(math.to_radians(rotation))

    // Draw shadow
    if shadow_offset_x != 0 || shadow_offset_y != 0 {
        rl.BeginBlendMode(.MULTIPLIED)
        rl.DrawRectanglePro(
            rl.Rectangle { pos_x + shadow_offset_x, pos_y + shadow_offset_y, l, w },
            rl.Vector2 { 0, w * 0.5 },
            rotation, shadow_color
        )
        rl.EndBlendMode()
    }

    // Draw marker
    rl.DrawRectanglePro(
        rl.Rectangle { pos_x, pos_y, l, w },
        rl.Vector2 { 0, w * 0.5 },
        rotation, color
    )
}

draw_hand :: proc(center_x, center_y, width, height, pivot_x, rotation, base_radius: f32, color: rl.Color, shadow_offset_x, shadow_offset_y: f32, shadow_color, highlight_color: rl.Color) {
    // Draw hand shadow
    if shadow_offset_x != 0 || shadow_offset_y != 0 {
        rl.BeginBlendMode(.MULTIPLIED)
        rl.DrawCircle(
            i32(center_x+shadow_offset_x), i32(center_y+shadow_offset_y),
            base_radius, shadow_color
        )
        rl.DrawRectanglePro(
            rl.Rectangle { center_x+shadow_offset_x, center_y+shadow_offset_y, width, height },
            rl.Vector2 { pivot_x, height*0.5 },
            rotation-90, shadow_color
        )
        rl.EndBlendMode()

        // Draw highlight
        highlight_offset_x := shadow_offset_x * 0.5
        highlight_offset_y := shadow_offset_y * 0.5
        rl.DrawCircle(
            i32(center_x-highlight_offset_x), i32(center_y-highlight_offset_y),
            base_radius, highlight_color
        )
        rl.DrawRectanglePro(
            rl.Rectangle { center_x-highlight_offset_x, center_y-highlight_offset_y, width, height },
            rl.Vector2 { pivot_x, height*0.5 },
            rotation-90, highlight_color
        )
    }

    // Draw hand
    rl.DrawCircle(
        i32(center_x), i32(center_y),
        base_radius, color
    )
    rl.DrawRectanglePro(
        rl.Rectangle { center_x, center_y, width, height },
        rl.Vector2 { pivot_x, height*0.5 },
        rotation-90, color
    )
}

update_ui :: proc() {
    mouse_pos := rl.GetMousePosition()

    if mouse_pos.y > 60 || mouse_pos.x > f32(60+30*len(themes)) do return

    for &t, i in themes {
        pos_x: i32 = 20 + i32(30*i)
        pos_y: i32 = 20

        is_hovered := rl.CheckCollisionPointCircle(mouse_pos, rl.Vector2 {f32(pos_x), f32(pos_y)}, 10)
        radius: f32 = (is_hovered || current_theme == &t) ? 12 : 10

        rl.DrawCircle(pos_x, pos_y, radius, t.theme)
        rl.DrawCircleLines(pos_x, pos_y, radius + 1, rl.WHITE)
        rl.DrawCircleLines(pos_x, pos_y, radius + 2, rl.BLACK)

        if is_hovered && rl.IsMouseButtonReleased(.LEFT) {
            source_theme = current_theme
            current_theme = &t
            anim_switch_time = time.now()._nsec
        }
    }
}

lerp_theme :: proc(anim, source, target: ^theme, t: f64) {
    lerp_color(&anim.bg, &source.bg, &target.bg, t)
    lerp_color(&anim.marker, &source.marker, &target.marker, t)
    lerp_color(&anim.marker_shadow, &source.marker_shadow, &target.marker_shadow, t)
    lerp_color(&anim.hour, &source.hour, &target.hour, t)
    lerp_color(&anim.minute, &source.minute, &target.minute, t)
    lerp_color(&anim.second, &source.second, &target.second, t)
    lerp_color(&anim.hand_shadow, &source.hand_shadow, &target.hand_shadow, t)
    lerp_color(&anim.hand_highlight, &source.hand_highlight, &target.hand_highlight, t)
    lerp_color(&anim.day, &source.day, &target.day, t)
}

lerp_color :: proc(anim, source, target: ^rl.Color, t: f64) {
    anim.r = u8(math.lerp(f64(source.r), f64(target.r), t))
    anim.g = u8(math.lerp(f64(source.g), f64(target.g), t))
    anim.b = u8(math.lerp(f64(source.b), f64(target.b), t))
    anim.a = u8(math.lerp(f64(source.a), f64(target.a), t))
}