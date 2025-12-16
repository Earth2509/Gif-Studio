module MouseCtl(
    input clk,
    input rst,
    inout ps2_clk,
    inout ps2_data,
    output reg [8:0] x_pos, // Relative Movement (Delta)
    output reg [8:0] y_pos, // Relative Movement (Delta)
    output reg left,
    output reg middle,
    output reg right,
    output reg new_event    // Pulses high when mouse moves/clicks
    );

    // 1. Clock Filtering (Debouncing)
    reg [3:0] ps2_clk_filter;
    reg ps2_clk_stable;
    
    always @(posedge clk) begin
        ps2_clk_filter <= {ps2_clk_filter[2:0], ps2_clk};
        if (ps2_clk_filter == 4'b1111) ps2_clk_stable <= 1;
        else if (ps2_clk_filter == 4'b0000) ps2_clk_stable <= 0;
    end

    // 2. Edge Detection
    reg prev_ps2_clk;
    always @(posedge clk) begin
        prev_ps2_clk <= ps2_clk_stable;
    end
    wire ps2_clk_negedge = (prev_ps2_clk && !ps2_clk_stable);

    // 3. Shift Register & Packet Processing
    reg [10:0] bit_count;
    reg [32:0] shift;

    always @(posedge clk) begin
        if (rst) begin
            bit_count <= 0;
            shift <= 0;
            new_event <= 0;
            x_pos <= 0; y_pos <= 0;
            left <= 0; middle <= 0; right <= 0;
        end 
        else if (ps2_clk_negedge) begin
            shift <= {ps2_data, shift[32:1]};
            bit_count <= bit_count + 1;
            new_event <= 0;
        end 
        else if (bit_count == 33) begin
            left   <= shift[1];  
            right  <= shift[2];  
            middle <= shift[3];  
            
            x_pos <= {shift[5], shift[19:12]}; 
            y_pos <= {shift[6], shift[30:23]}; 
            
            new_event <= 1; 
            bit_count <= 0; 
        end 
        else begin
            new_event <= 0; 
        end
    end
endmodule