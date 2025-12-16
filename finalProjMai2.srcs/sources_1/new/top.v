module top_module(
    input clk,              // 100MHz Basys3 Clock
    input [15:0] sw,        // sw[0]=Reset, sw[4]=Onion, sw[5]=Eraser, sw[3]=Mode, sw[15]=ROM, sw[14]=RAM1, sw[13]=RAM2
    input [4:0] btn,        // btn[0]=Paint, btn[1]=U, btn[2]=L, btn[3]=R, btn[4]=D
    output [3:0] vgaRed,
    output [3:0] vgaGreen,
    output [3:0] vgaBlue,
    output Hsync,
    output Vsync
    );

    // =========================================================================
    // 1. SYSTEM SETUP & CLOCKS
    // =========================================================================
    wire MODE_DRAW  = sw[3];      
    wire RST_GLOBAL = sw[0]; // Acts as System Reset AND Ram Clear
    
    wire SW_ROM_ON  = sw[15];
    wire SW_RAM1_ON = sw[14];     
    wire SW_RAM2_ON = sw[13];     
    wire SW_ONION   = sw[4];
    wire SW_ERASER  = sw[5];      

    reg [1:0] clk_div = 0;
    always @(posedge clk) clk_div <= clk_div + 1;
    wire clk_25 = clk_div[1];

    wire [9:0] pix_x, pix_y;
    wire video_on;
    vga_controller vga_inst(
        .clk_25MHz(clk_25), .reset(RST_GLOBAL), 
        .video_on(video_on), .hsync(Hsync), .vsync(Vsync), 
        .x(pix_x), .y(pix_y)
    );

    // =========================================================================
    // 2. STATE LOGIC (UI, Positions, Tools)
    // =========================================================================
    
    // --- INPUTS ---
    reg prev_btn0, prev_sw_rom, prev_sw_ram1, prev_sw_ram2;
    wire click_posedge = (btn[0] && !prev_btn0);
    wire rom_posedge   = (SW_ROM_ON  && !prev_sw_rom);
    wire ram1_posedge  = (SW_RAM1_ON && !prev_sw_ram1);
    wire ram2_posedge  = (SW_RAM2_ON && !prev_sw_ram2);

    // --- REGISTERS ---
    reg [1:0] play_focus_id = 0; 
    wire [1:0] draw_focus_id = (SW_RAM2_ON) ? 2 : (SW_RAM1_ON) ? 1 : 0;
    wire [1:0] current_target = (MODE_DRAW) ? draw_focus_id : play_focus_id;

    // Objects
    reg [9:0] rom_x = 288, rom_y = 208; reg [1:0] rom_scale = 0;
    reg [9:0] ram1_x = 288, ram1_y = 208; reg [1:0] ram1_scale = 0;
    reg [9:0] ram2_x = 288, ram2_y = 208; reg [1:0] ram2_scale = 0;
    
    // Tools
    reg [9:0] cursor_x = 320, cursor_y = 240;
    reg [1:0] edit_frame = 0; 
    reg [11:0] selected_color = 12'hF00; 
    reg [2:0] brush_idx = 0;

    // Animation
    reg [5:0] anim_timer = 0;
    reg [2:0] rom_anim_frame = 0;   
    reg [1:0] ram_anim_frame = 0;   
    
    // Timing
    reg vsync_prev = 0;
    wire vsync_posedge = (Vsync == 1) && (vsync_prev == 0);
    reg [23:0] speed_latch_timer = 0;
    wire [9:0] cursor_speed = (speed_latch_timer > 0) ? 1 : 2;

    // --- DERIVED VALUES ---
    wire [11:0] paint_color = (SW_ERASER) ? 12'h000 : selected_color;
    
    // Dynamic Max Size (For clamping movement)
    wire [9:0] rom_max_x = 640 - (64 << rom_scale); wire [9:0] rom_max_y = 480 - (64 << rom_scale);
    wire [9:0] ram1_max_x = 640 - (64 << ram1_scale); wire [9:0] ram1_max_y = 480 - (64 << ram1_scale);
    wire [9:0] ram2_max_x = 640 - (64 << ram2_scale); wire [9:0] ram2_max_y = 480 - (64 << ram2_scale);

    // --- UI CONSTANTS ---
    parameter CANVAS_CENTER_X = 288;
    parameter CANVAS_CENTER_Y = 208;
    parameter BTN_Y = 280;      
    parameter BTN_L_X = 280; parameter BTN_R_X = 344; parameter BTN_SIZE = 16;    
    parameter PAL_Y = 185; parameter PAL_SIZE = 12;
    parameter PAL_X0 = 288; parameter PAL_X1 = 304; parameter PAL_X2 = 320; parameter PAL_X3 = 336; 
    parameter TAB_Y = 185; parameter TAB1_X = 250; parameter TAB2_X = 265; parameter TAB_W = 10;
    // Brush UI
    parameter BRUSH_BTN_SIZE = 16;
    parameter BRUSH_COL1_X = 360; parameter BRUSH_COL2_X = 380; 
    parameter BRUSH_Y0 = 210; parameter BRUSH_Y1 = 230; parameter BRUSH_Y2 = 250; 

    // --- MAIN STATE UPDATE BLOCK ---
    always @(posedge clk) begin
        // Signal Updates
        vsync_prev <= Vsync;
        prev_sw_rom <= SW_ROM_ON; prev_sw_ram1 <= SW_RAM1_ON; prev_sw_ram2 <= SW_RAM2_ON;
        prev_btn0 <= btn[0];
        
        // Jitter Latch
        if (btn[0]) speed_latch_timer <= 24'hF_FFFF; 
        else if (speed_latch_timer > 0) speed_latch_timer <= speed_latch_timer - 1;

        if (RST_GLOBAL) begin
            rom_x <= 288; rom_y <= 208;
            ram1_x <= 288; ram1_y <= 208;
            ram2_x <= 288; ram2_y <= 208;
            cursor_x <= 320; cursor_y <= 240;
            edit_frame <= 0; play_focus_id <= 0;
            selected_color <= 12'hF00;
            brush_idx <= 0;
        end else begin
            
            // SELECTION
            if (rom_posedge)  play_focus_id <= 0; 
            if (ram1_posedge) play_focus_id <= 1; 
            if (ram2_posedge) play_focus_id <= 2; 
            
            // SCALING
            if (current_target == 0 && SW_ROM_ON)        rom_scale <= sw[2:1];
            else if (current_target == 1 && SW_RAM1_ON)  ram1_scale <= sw[2:1];
            else if (current_target == 2 && SW_RAM2_ON)  ram2_scale <= sw[2:1];

            // CLICK LOGIC (UI)
            if (MODE_DRAW && click_posedge) begin
                // Frames
                if (cursor_x >= BTN_L_X && cursor_x < BTN_L_X+BTN_SIZE && cursor_y >= BTN_Y && cursor_y < BTN_Y+BTN_SIZE)
                    edit_frame <= (edit_frame > 0) ? edit_frame - 1 : 3;
                if (cursor_x >= BTN_R_X && cursor_x < BTN_R_X+BTN_SIZE && cursor_y >= BTN_Y && cursor_y < BTN_Y+BTN_SIZE)
                    edit_frame <= (edit_frame < 3) ? edit_frame + 1 : 0;
                
                // Palette
                if (cursor_y >= PAL_Y && cursor_y < PAL_Y+PAL_SIZE) begin
                    if (cursor_x >= PAL_X0 && cursor_x < PAL_X0+PAL_SIZE) selected_color <= 12'hF00;
                    if (cursor_x >= PAL_X1 && cursor_x < PAL_X1+PAL_SIZE) selected_color <= 12'h00F;
                    if (cursor_x >= PAL_X2 && cursor_x < PAL_X2+PAL_SIZE) selected_color <= 12'h0F0;
                    if (cursor_x >= PAL_X3 && cursor_x < PAL_X3+PAL_SIZE) selected_color <= 12'hFB1;
                end
                
                // Brush Buttons
                if (cursor_x >= BRUSH_COL1_X && cursor_x < BRUSH_COL1_X+BRUSH_BTN_SIZE) begin
                    if (cursor_y >= BRUSH_Y0 && cursor_y < BRUSH_Y0+BRUSH_BTN_SIZE) brush_idx <= 0; 
                    if (cursor_y >= BRUSH_Y1 && cursor_y < BRUSH_Y1+BRUSH_BTN_SIZE) brush_idx <= 1; 
                    if (cursor_y >= BRUSH_Y2 && cursor_y < BRUSH_Y2+BRUSH_BTN_SIZE) brush_idx <= 2; 
                end
                if (cursor_x >= BRUSH_COL2_X && cursor_x < BRUSH_COL2_X+BRUSH_BTN_SIZE) begin
                    if (cursor_y >= BRUSH_Y0 && cursor_y < BRUSH_Y0+BRUSH_BTN_SIZE) brush_idx <= 3; 
                    if (cursor_y >= BRUSH_Y1 && cursor_y < BRUSH_Y1+BRUSH_BTN_SIZE) brush_idx <= 4; 
                    if (cursor_y >= BRUSH_Y2 && cursor_y < BRUSH_Y2+BRUSH_BTN_SIZE) brush_idx <= 5; 
                end
            end

            // MOVEMENT (Vsync Synced)
            if (vsync_posedge) begin
                if (MODE_DRAW) begin
                    if (btn[1] && cursor_y > cursor_speed)     cursor_y <= cursor_y - cursor_speed;
                    if (btn[2] && cursor_x > cursor_speed)     cursor_x <= cursor_x - cursor_speed;
                    if (btn[3] && cursor_x < 638)              cursor_x <= cursor_x + cursor_speed;
                    if (btn[4] && cursor_y < 478)              cursor_y <= cursor_y + cursor_speed;
                end else begin
                    // Play Mode Movement
                    if (play_focus_id == 0 && SW_ROM_ON) begin 
                         if (rom_x > rom_max_x) rom_x <= rom_max_x;
                         else if (rom_y > rom_max_y) rom_y <= rom_max_y;
                         else begin
                            if (btn[1] && rom_y > 2) rom_y <= rom_y - 2;
                            if (btn[2] && rom_x > 2) rom_x <= rom_x - 2;
                            if (btn[3] && rom_x < rom_max_x) rom_x <= rom_x + 2;
                            if (btn[4] && rom_y < rom_max_y) rom_y <= rom_y + 2;
                         end
                    end 
                    else if (play_focus_id == 1 && SW_RAM1_ON) begin 
                         if (ram1_x > ram1_max_x) ram1_x <= ram1_max_x;
                         else if (ram1_y > ram1_max_y) ram1_y <= ram1_max_y;
                         else begin
                            if (btn[1] && ram1_y > 2) ram1_y <= ram1_y - 2;
                            if (btn[2] && ram1_x > 2) ram1_x <= ram1_x - 2;
                            if (btn[3] && ram1_x < ram1_max_x) ram1_x <= ram1_x + 2;
                            if (btn[4] && ram1_y < ram1_max_y) ram1_y <= ram1_y + 2;
                         end
                    end
                    else if (play_focus_id == 2 && SW_RAM2_ON) begin 
                         if (ram2_x > ram2_max_x) ram2_x <= ram2_max_x;
                         else if (ram2_y > ram2_max_y) ram2_y <= ram2_max_y;
                         else begin
                            if (btn[1] && ram2_y > 2) ram2_y <= ram2_y - 2;
                            if (btn[2] && ram2_x > 2) ram2_x <= ram2_x - 2;
                            if (btn[3] && ram2_x < ram2_max_x) ram2_x <= ram2_x + 2;
                            if (btn[4] && ram2_y < ram2_max_y) ram2_y <= ram2_y + 2;
                         end
                    end
                end

                // Animation Counter
                if (anim_timer > 8) begin
                    anim_timer <= 0;
                    rom_anim_frame <= (rom_anim_frame == 5) ? 0 : rom_anim_frame + 1;
                    if (!MODE_DRAW) ram_anim_frame <= (ram_anim_frame == 3) ? 0 : ram_anim_frame + 1;
                end else begin
                    anim_timer <= anim_timer + 1;
                end
            end
        end
    end

    // =========================================================================
    // 3. RENDERERS & RAM LOGIC
    // =========================================================================
    
    wire [1:0] ghost_frame_idx = (edit_frame == 0) ? 3 : (edit_frame - 1);
    wire [1:0] curr_frame_idx = (MODE_DRAW) ? edit_frame : ram_anim_frame;
    
    // --- RESET / CLEAR LOGIC ---
    // Counter to iterate through all 16384 addresses (4 frames * 4096 px)
    reg [13:0] reset_counter;
    always @(posedge clk) begin
        if (RST_GLOBAL) reset_counter <= reset_counter + 1;
        else reset_counter <= 0;
    end

    // --- CURSOR & BRUSH CALCS ---
    // Auto-Shrink Logic (Grace Margin 5px)
    parameter GRACE_MARGIN = 5; 
    wire in_ui_zone = (cursor_y < CANVAS_CENTER_Y - GRACE_MARGIN) || 
                      (cursor_y >= CANVAS_CENTER_Y + 64 + GRACE_MARGIN) ||
                      (cursor_x >= CANVAS_CENTER_X + 64 + GRACE_MARGIN) || 
                      (cursor_x < CANVAS_CENTER_X - GRACE_MARGIN);
    
    wire [2:0] effective_brush_idx = (in_ui_zone) ? 3'd0 : brush_idx;
    wire [5:0] brush_size_display = 1 << effective_brush_idx;

    // Visual Cursor Check
    wire is_cursor = (pix_x >= cursor_x && pix_x < cursor_x + brush_size_display && 
                      pix_y >= cursor_y && pix_y < cursor_y + brush_size_display);

    // Multi-Pixel Write Logic (Spray)
    reg [9:0] write_counter;
    always @(posedge clk) write_counter <= write_counter + 1;

    reg [4:0] off_x, off_y;
    always @(*) begin
        case(effective_brush_idx)
            0: begin off_x = 0; off_y = 0; end
            1: begin off_x = write_counter[0]; off_y = write_counter[1]; end 
            2: begin off_x = write_counter[1:0]; off_y = write_counter[3:2]; end
            3: begin off_x = write_counter[2:0]; off_y = write_counter[5:3]; end
            4: begin off_x = write_counter[3:0]; off_y = write_counter[7:4]; end
            5: begin off_x = write_counter[4:0]; off_y = write_counter[9:5]; end
            default: begin off_x = 0; off_y = 0; end
        endcase
    end

    wire [9:0] target_x = cursor_x + off_x;
    wire [9:0] target_y = cursor_y + off_y;

    // Cheat Fix: Clamp 1px border
    wire is_safe_x = (target_x >= CANVAS_CENTER_X + 1) && (target_x <= CANVAS_CENTER_X + 62);
    wire is_safe_y = (target_y >= CANVAS_CENTER_Y) && (target_y <= CANVAS_CENTER_Y + 63);
    wire safe_to_write = is_safe_x && is_safe_y;

    wire [5:0] write_col = target_x - CANVAS_CENTER_X;
    wire [5:0] write_row = target_y - CANVAS_CENTER_Y;
    
    // --- PIPELINE & RESET MUXING ---
    // If Resetting: Addr = Counter, Data = 0, WE = 1
    // If Painting:  Addr = Cursor,  Data = Paint, WE = Btn
    
    wire [13:0] addr_mux = (RST_GLOBAL) ? reset_counter : ((edit_frame * 4096) + (write_row * 64) + write_col);
    wire [11:0] data_mux = (RST_GLOBAL) ? 12'h000 : paint_color;
    wire we_mux = (RST_GLOBAL) ? 1'b1 : (MODE_DRAW && btn[0] && safe_to_write);

    // Pipeline Registers
    reg [13:0] write_addr_stable;
    reg [11:0] write_data_stable;
    reg we_stable;

    always @(posedge clk) begin
        write_addr_stable <= addr_mux;
        write_data_stable <= data_mux;
        we_stable <= we_mux;
    end

    // --- ROM ---
    wire in_rom_box = (pix_x >= rom_x) && (pix_x < rom_x + (64<<rom_scale)) &&
                      (pix_y >= rom_y) && (pix_y < rom_y + (64<<rom_scale));
    wire [5:0] rom_col = (pix_x - rom_x) >> rom_scale; 
    wire [5:0] rom_row = (pix_y - rom_y) >> rom_scale;
    wire [14:0] rom_addr = (rom_anim_frame * 4096) + (rom_row * 64) + rom_col;
    wire [11:0] rom_pixel;
    blk_mem_gen_0 sprite_rom (.clka(clk), .addra(rom_addr), .douta(rom_pixel));

    // --- RAMS ---
    // Canvas 1 Display
    wire [9:0] active_ram1_x = (MODE_DRAW && draw_focus_id == 1) ? CANVAS_CENTER_X : ram1_x;
    wire [9:0] active_ram1_y = (MODE_DRAW && draw_focus_id == 1) ? CANVAS_CENTER_Y : ram1_y;
    wire [1:0] active_ram1_scale = (MODE_DRAW && draw_focus_id == 1) ? 0 : ram1_scale;
    
    wire in_ram1_box = (pix_x >= active_ram1_x + 1) && (pix_x < active_ram1_x + (64<<active_ram1_scale) - 1) &&
                       (pix_y >= active_ram1_y) && (pix_y < active_ram1_y + (64<<active_ram1_scale));
    
    wire [5:0] ram1_col = (pix_x - active_ram1_x) >> active_ram1_scale;
    wire [5:0] ram1_row = (pix_y - active_ram1_y) >> active_ram1_scale;
    wire [13:0] ram1_read_addr = (curr_frame_idx * 4096) + (ram1_row * 64) + ram1_col;
    wire [13:0] ghost1_read_addr = (ghost_frame_idx * 4096) + (ram1_row * 64) + ram1_col;
    wire [11:0] ram1_pixel_out, ghost1_pixel_out;
    
    wire we_ram1 = we_stable && (draw_focus_id == 1 || RST_GLOBAL);

    blk_mem_gen_1 ram1_master (.clka(clk), .wea(we_ram1), .addra(write_addr_stable), .dina(write_data_stable), 
                               .clkb(clk), .addrb(ram1_read_addr), .doutb(ram1_pixel_out), .web(0), .dinb(0));
    blk_mem_gen_1 ram1_mirror (.clka(clk), .wea(we_ram1), .addra(write_addr_stable), .dina(write_data_stable), 
                               .clkb(clk), .addrb(ghost1_read_addr), .doutb(ghost1_pixel_out), .web(0), .dinb(0));

    // Canvas 2 Display
    wire [9:0] active_ram2_x = (MODE_DRAW && draw_focus_id == 2) ? CANVAS_CENTER_X : ram2_x;
    wire [9:0] active_ram2_y = (MODE_DRAW && draw_focus_id == 2) ? CANVAS_CENTER_Y : ram2_y;
    wire [1:0] active_ram2_scale = (MODE_DRAW && draw_focus_id == 2) ? 0 : ram2_scale;

    wire in_ram2_box = (pix_x >= active_ram2_x + 1) && (pix_x < active_ram2_x + (64<<active_ram2_scale) - 1) &&
                       (pix_y >= active_ram2_y) && (pix_y < active_ram2_y + (64<<active_ram2_scale));
    
    wire [5:0] ram2_col = (pix_x - active_ram2_x) >> active_ram2_scale;
    wire [5:0] ram2_row = (pix_y - active_ram2_y) >> active_ram2_scale;
    wire [13:0] ram2_read_addr = (curr_frame_idx * 4096) + (ram2_row * 64) + ram2_col;
    wire [13:0] ghost2_read_addr = (ghost_frame_idx * 4096) + (ram2_row * 64) + ram2_col;
    wire [11:0] ram2_pixel_out, ghost2_pixel_out;
    
    wire we_ram2 = we_stable && (draw_focus_id == 2 || RST_GLOBAL);

    blk_mem_gen_1 ram2_master (.clka(clk), .wea(we_ram2), .addra(write_addr_stable), .dina(write_data_stable), 
                               .clkb(clk), .addrb(ram2_read_addr), .doutb(ram2_pixel_out), .web(0), .dinb(0));
    blk_mem_gen_1 ram2_mirror (.clka(clk), .wea(we_ram2), .addra(write_addr_stable), .dina(write_data_stable), 
                               .clkb(clk), .addrb(ghost2_read_addr), .doutb(ghost2_pixel_out), .web(0), .dinb(0));


    // =========================================================================
    // 4. UI OBJECTS
    // =========================================================================
    
    wire UI_VISIBLE = MODE_DRAW;

    // Palette
    wire in_pal_y = (pix_y >= PAL_Y && pix_y < PAL_Y+PAL_SIZE);
    wire in_pal_0 = in_pal_y && (pix_x >= PAL_X0 && pix_x < PAL_X0+PAL_SIZE);
    wire in_pal_1 = in_pal_y && (pix_x >= PAL_X1 && pix_x < PAL_X1+PAL_SIZE);
    wire in_pal_2 = in_pal_y && (pix_x >= PAL_X2 && pix_x < PAL_X2+PAL_SIZE);
    wire in_pal_3 = in_pal_y && (pix_x >= PAL_X3 && pix_x < PAL_X3+PAL_SIZE);

    wire is_border_0 = (selected_color == 12'hF00) && in_pal_0 && ((pix_x==PAL_X0)||(pix_x==PAL_X0+11)||(pix_y==PAL_Y)||(pix_y==PAL_Y+11));
    wire is_border_1 = (selected_color == 12'h00F) && in_pal_1 && ((pix_x==PAL_X1)||(pix_x==PAL_X1+11)||(pix_y==PAL_Y)||(pix_y==PAL_Y+11));
    wire is_border_2 = (selected_color == 12'h0F0) && in_pal_2 && ((pix_x==PAL_X2)||(pix_x==PAL_X2+11)||(pix_y==PAL_Y)||(pix_y==PAL_Y+11));
    wire is_border_3 = (selected_color == 12'hFB1) && in_pal_3 && ((pix_x==PAL_X3)||(pix_x==PAL_X3+11)||(pix_y==PAL_Y)||(pix_y==PAL_Y+11));
    wire is_any_border = is_border_0 || is_border_1 || is_border_2 || is_border_3;

    // Tabs
    wire in_tab1 = (pix_y >= TAB_Y && pix_y < TAB_Y+12) && (pix_x >= TAB1_X && pix_x < TAB1_X+TAB_W);
    wire in_tab2 = (pix_y >= TAB_Y && pix_y < TAB_Y+12) && (pix_x >= TAB2_X && pix_x < TAB2_X+TAB_W);
    wire tab_bar_y = (pix_y >= TAB_Y + 2 && pix_y <= TAB_Y + 9);
    wire is_I  = in_tab1 && (pix_x == TAB1_X + 5) && tab_bar_y; 
    wire is_II = in_tab2 && ((pix_x == TAB2_X + 3) || (pix_x == TAB2_X + 7)) && tab_bar_y;

    // Brush Buttons UI
    wire in_brush0 = (pix_x >= BRUSH_COL1_X && pix_x < BRUSH_COL1_X+BRUSH_BTN_SIZE && pix_y >= BRUSH_Y0 && pix_y < BRUSH_Y0+BRUSH_BTN_SIZE);
    wire in_brush1 = (pix_x >= BRUSH_COL1_X && pix_x < BRUSH_COL1_X+BRUSH_BTN_SIZE && pix_y >= BRUSH_Y1 && pix_y < BRUSH_Y1+BRUSH_BTN_SIZE);
    wire in_brush2 = (pix_x >= BRUSH_COL1_X && pix_x < BRUSH_COL1_X+BRUSH_BTN_SIZE && pix_y >= BRUSH_Y2 && pix_y < BRUSH_Y2+BRUSH_BTN_SIZE);
    wire in_brush3 = (pix_x >= BRUSH_COL2_X && pix_x < BRUSH_COL2_X+BRUSH_BTN_SIZE && pix_y >= BRUSH_Y0 && pix_y < BRUSH_Y0+BRUSH_BTN_SIZE);
    wire in_brush4 = (pix_x >= BRUSH_COL2_X && pix_x < BRUSH_COL2_X+BRUSH_BTN_SIZE && pix_y >= BRUSH_Y1 && pix_y < BRUSH_Y1+BRUSH_BTN_SIZE);
    wire in_brush5 = (pix_x >= BRUSH_COL2_X && pix_x < BRUSH_COL2_X+BRUSH_BTN_SIZE && pix_y >= BRUSH_Y2 && pix_y < BRUSH_Y2+BRUSH_BTN_SIZE);
    
    // Icons
    wire is_icon0 = in_brush0 && (pix_x >= BRUSH_COL1_X+7 && pix_x <= BRUSH_COL1_X+8 && pix_y >= BRUSH_Y0+7 && pix_y <= BRUSH_Y0+8);
    wire is_icon1 = in_brush1 && (pix_x >= BRUSH_COL1_X+6 && pix_x <= BRUSH_COL1_X+9 && pix_y >= BRUSH_Y1+6 && pix_y <= BRUSH_Y1+9);
    wire is_icon2 = in_brush2 && (pix_x >= BRUSH_COL1_X+4 && pix_x <= BRUSH_COL1_X+11 && pix_y >= BRUSH_Y2+4 && pix_y <= BRUSH_Y2+11);
    wire is_icon3 = in_brush3 && (pix_x >= BRUSH_COL2_X+5 && pix_x <= BRUSH_COL2_X+10 && pix_y >= BRUSH_Y0+5 && pix_y <= BRUSH_Y0+10);
    wire is_icon4 = in_brush4 && (pix_x >= BRUSH_COL2_X+3 && pix_x <= BRUSH_COL2_X+12 && pix_y >= BRUSH_Y1+3 && pix_y <= BRUSH_Y1+12);
    wire is_icon5 = in_brush5 && (pix_x >= BRUSH_COL2_X+2 && pix_x <= BRUSH_COL2_X+13 && pix_y >= BRUSH_Y2+2 && pix_y <= BRUSH_Y2+13);
    
    // Borders
    wire b0_sel = (brush_idx == 0) && in_brush0 && ((pix_x==BRUSH_COL1_X)||(pix_x==BRUSH_COL1_X+15)||(pix_y==BRUSH_Y0)||(pix_y==BRUSH_Y0+15));
    wire b1_sel = (brush_idx == 1) && in_brush1 && ((pix_x==BRUSH_COL1_X)||(pix_x==BRUSH_COL1_X+15)||(pix_y==BRUSH_Y1)||(pix_y==BRUSH_Y1+15));
    wire b2_sel = (brush_idx == 2) && in_brush2 && ((pix_x==BRUSH_COL1_X)||(pix_x==BRUSH_COL1_X+15)||(pix_y==BRUSH_Y2)||(pix_y==BRUSH_Y2+15));
    wire b3_sel = (brush_idx == 3) && in_brush3 && ((pix_x==BRUSH_COL2_X)||(pix_x==BRUSH_COL2_X+15)||(pix_y==BRUSH_Y0)||(pix_y==BRUSH_Y0+15));
    wire b4_sel = (brush_idx == 4) && in_brush4 && ((pix_x==BRUSH_COL2_X)||(pix_x==BRUSH_COL2_X+15)||(pix_y==BRUSH_Y1)||(pix_y==BRUSH_Y1+15));
    wire b5_sel = (brush_idx == 5) && in_brush5 && ((pix_x==BRUSH_COL2_X)||(pix_x==BRUSH_COL2_X+15)||(pix_y==BRUSH_Y2)||(pix_y==BRUSH_Y2+15));
    wire is_brush_border = b0_sel || b1_sel || b2_sel || b3_sel || b4_sel || b5_sel;
    wire any_brush = in_brush0 || in_brush1 || in_brush2 || in_brush3 || in_brush4 || in_brush5;
    wire any_icon  = is_icon0  || is_icon1  || is_icon2  || is_icon3  || is_icon4  || is_icon5;

    // Buttons
    wire in_btn_l = (pix_x >= BTN_L_X && pix_x < BTN_L_X+BTN_SIZE && pix_y >= BTN_Y && pix_y < BTN_Y+BTN_SIZE);
    wire in_btn_r = (pix_x >= BTN_R_X && pix_x < BTN_R_X+BTN_SIZE && pix_y >= BTN_Y && pix_y < BTN_Y+BTN_SIZE);

    // Indicators
    wire in_indicator_y = (pix_y >= BTN_Y+4) && (pix_y < BTN_Y+12);
    wire dot0 = (pix_x >= 302 && pix_x < 308); wire dot1 = (pix_x >= 312 && pix_x < 318);
    wire dot2 = (pix_x >= 322 && pix_x < 328); wire dot3 = (pix_x >= 332 && pix_x < 338);
    wire is_dot = in_indicator_y && (dot0 || dot1 || dot2 || dot3);
    wire is_active_dot = in_indicator_y && (
        (edit_frame == 0 && dot0) || (edit_frame == 1 && dot1) ||
        (edit_frame == 2 && dot2) || (edit_frame == 3 && dot3)
    );
    
    // Canvas Frame
    wire is_canvas_frame = (pix_x >= 287 && pix_x <= 352 && pix_y >= 207 && pix_y <= 272) &&
                           !((pix_x > 287 && pix_x < 352) && (pix_y > 207 && pix_y < 272));

    // =========================================================================
    // 5. OUTPUT MIXER
    // =========================================================================
    reg [11:0] rgb_out;
    
    always @(*) begin
        if (!video_on) begin
            rgb_out = 12'h000;
        end 
        
        // --- DRAW MODE ---
        else if (MODE_DRAW) begin
            
            // 1. Cursor
            if (is_cursor) rgb_out = 12'h000;
            
            // 2. UI Elements
            else if (UI_VISIBLE && is_any_border) rgb_out = 12'h000;
            else if (UI_VISIBLE && in_pal_0)      rgb_out = 12'hF00; 
            else if (UI_VISIBLE && in_pal_1)      rgb_out = 12'h00F; 
            else if (UI_VISIBLE && in_pal_2)      rgb_out = 12'h0F0; 
            else if (UI_VISIBLE && in_pal_3)      rgb_out = 12'hFB1; 
            
            // Brush UI
            else if (UI_VISIBLE && is_brush_border) rgb_out = 12'h000;
            else if (UI_VISIBLE && any_icon)        rgb_out = 12'h000; 
            else if (UI_VISIBLE && any_brush)       rgb_out = 12'hFFF;

            else if (UI_VISIBLE && in_tab1) begin
                 if (is_I) rgb_out = 12'hFFF; 
                 else rgb_out = (draw_focus_id == 1) ? 12'h000 : 12'h888;
            end
            else if (UI_VISIBLE && in_tab2) begin
                 if (is_II) rgb_out = 12'hFFF; 
                 else rgb_out = (draw_focus_id == 2) ? 12'h000 : 12'h888; 
            end

            else if (UI_VISIBLE && in_btn_l) begin
                 if ((pix_x - BTN_L_X) < (pix_y > BTN_Y+8 ? pix_y - (BTN_Y+8) : (BTN_Y+8) - pix_y)) rgb_out = 12'h222; 
                 else rgb_out = 12'hF92; 
            end
            else if (UI_VISIBLE && in_btn_r) begin
                 if ((BTN_R_X + 16 - pix_x) < (pix_y > BTN_Y+8 ? pix_y - (BTN_Y+8) : (BTN_Y+8) - pix_y)) rgb_out = 12'h222; 
                 else rgb_out = 12'hF92; 
            end
            else if (UI_VISIBLE && is_dot) begin
                 if (is_active_dot) rgb_out = 12'h000; else rgb_out = 12'hFFF; 
            end
            
            // Frame Border
            else if (is_canvas_frame) rgb_out = 12'h000;
            
            // 3. Active Canvas
            else if (draw_focus_id == 2 && in_ram2_box) begin
                 if (ram2_pixel_out != 12'h000) rgb_out = ram2_pixel_out;
                 else if (SW_ONION && ghost2_pixel_out != 12'h000) begin
                     case (ghost2_pixel_out)
                        12'hF00: rgb_out = 12'hF88; 12'h00F: rgb_out = 12'h88F; 
                        12'h0F0: rgb_out = 12'h6D6; 12'hFB1: rgb_out = 12'hEB6; 
                        default: rgb_out = 12'hEEE; 
                     endcase
                 end else rgb_out = 12'hFFF; 
            end
            else if (draw_focus_id == 1 && in_ram1_box) begin
                 if (ram1_pixel_out != 12'h000) rgb_out = ram1_pixel_out;
                 else if (SW_ONION && ghost1_pixel_out != 12'h000) begin
                     case (ghost1_pixel_out)
                        12'hF00: rgb_out = 12'hF88; 12'h00F: rgb_out = 12'h88F; 
                        12'h0F0: rgb_out = 12'h6D6; 12'hFB1: rgb_out = 12'hEB6; 
                        default: rgb_out = 12'hEEE; 
                     endcase
                 end else rgb_out = 12'hFFF; 
            end
            
            // 4. Grey Wall
            else begin
                 rgb_out = 12'hCCC; 
            end
        end
        
        // --- PLAY MODE ---
        else begin
            if (SW_RAM2_ON && in_ram2_box && ram2_pixel_out != 12'h000) rgb_out = ram2_pixel_out;
            else if (SW_RAM1_ON && in_ram1_box && ram1_pixel_out != 12'h000) rgb_out = ram1_pixel_out;
            else if (SW_ROM_ON && in_rom_box && rom_pixel != 12'hFFF) rgb_out = rom_pixel;
            else rgb_out = 12'hFFF; 
        end
    end

    assign vgaRed = rgb_out[11:8];
    assign vgaGreen = rgb_out[7:4];
    assign vgaBlue = rgb_out[3:0];

endmodule