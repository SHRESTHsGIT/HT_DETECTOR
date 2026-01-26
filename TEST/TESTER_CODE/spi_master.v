`timescale 1ns/1ps
module top(
    input  wire [7:0] in_data,
    input  wire       clk,
    input  wire [1:0] addr,
    input  wire       wr,
    input  wire       rd,
    input  wire       cs,
    output reg  [7:0] out_data,
    inout             mosi,
    input             miso,
    inout             sclk
);

    reg        sclk_buf;
    reg        mosi_buf;
    reg        busy;
    reg [7:0]  in_buf;
    reg [7:0]  out_buf;
    reg [7:0]  clk_cnt;
    reg [7:0]  clk_div;
    reg [4:0]  cnt;

    assign sclk = sclk_buf;
    assign mosi = mosi_buf;

    integer i;
    initial begin
        sclk_buf = 1'b0;
        mosi_buf = 1'b0;
        busy     = 1'b0;
        in_buf   = 8'd0;
        out_buf  = 8'd0;
        clk_cnt  = 8'd0;
        clk_div  = 8'd0;
        cnt      = 5'd0;
        out_data = 8'bx;
    end

    always @(posedge clk) begin
        if (sclk_buf) begin
            out_buf <= (out_buf << 1);
            out_buf[0] <= miso;
        end
    end

    always @(posedge clk) begin
        out_data <= 8'bx;
        if (cs && rd) begin
            case (addr)
                2'b00: out_data <= out_buf;
                2'b01: out_data <= {7'b0, busy};
                2'b10: out_data <= clk_div;
                default: out_data <= out_data;
            endcase
        end
    end

    always @(posedge clk) begin
        if (!busy) begin
            if (cs && wr) begin
                case (addr)
                    2'b00: begin
                        in_buf <= in_data;
                        busy   <= 1'b1;
                        cnt    <= 5'd0;
                    end
                    2'b10: begin
                        in_buf <= clk_div;
                    end
                    default: in_buf <= in_buf;
                endcase
            end else if (cs && rd) begin
                busy <= 1'b1;
                cnt  <= 5'd0;
            end
        end else begin
            clk_cnt <= clk_cnt + 8'd1;
            if (clk_cnt >= clk_div) begin
                clk_cnt <= 8'd0;
                if ((cnt % 2) == 0) begin
                    mosi_buf <= in_buf[7];
                    in_buf <= in_buf << 1;
                end
                if (cnt > 0 && cnt < 17)
                    sclk_buf <= ~sclk_buf;
                if (cnt >= 17) begin
                    cnt  <= 5'd0;
                    busy <= 1'b0;
                end else begin
                    cnt <= cnt + 5'd1;
                end
            end
        end
    end

endmodule
