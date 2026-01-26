module uart_tx #(
    parameter CLK_FREQ = 50_000_000,  // 50 MHz
    parameter BAUD_RATE = 115200
)(
    input  logic       clk,
    input  logic       rst_n,
    input  logic [7:0] tx_data,
    input  logic       tx_valid,
    output logic       tx_ready,
    output logic       tx_out
);

    // Calculate baud rate divisor
    localparam int DIVISOR = CLK_FREQ / BAUD_RATE;
    
    // State machine states
    typedef enum logic [2:0] {
        IDLE,
        START_BIT,
        DATA_BITS,
        STOP_BIT
    } state_t;
    
    state_t state, next_state;
    
    // Internal registers
    logic [7:0] shift_reg;
    logic [2:0] bit_counter;
    logic [$clog2(DIVISOR)-1:0] baud_counter;
    logic baud_tick;
    
    // Baud rate generator
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            baud_counter <= '0;
            baud_tick <= 1'b0;
        end else begin
            if (baud_counter == DIVISOR - 1) begin
                baud_counter <= '0;
                baud_tick <= 1'b1;
            end else begin
                baud_counter <= baud_counter + 1;
                baud_tick <= 1'b0;
            end
        end
    end
    
    // State machine - sequential logic
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            state <= IDLE;
        else
            state <= next_state;
    end
    
    // State machine - combinational logic
    always_comb begin
        next_state = state;
        
        case (state)
            IDLE: begin
                if (tx_valid)
                    next_state = START_BIT;
            end
            
            START_BIT: begin
                if (baud_tick)
                    next_state = DATA_BITS;
            end
            
            DATA_BITS: begin
                if (baud_tick && bit_counter == 7)
                    next_state = STOP_BIT;
            end
            
            STOP_BIT: begin
                if (baud_tick)
                    next_state = IDLE;
            end
            
            default: next_state = IDLE;
        endcase
    end
    
    // Data path logic
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            shift_reg <= '0;
            bit_counter <= '0;
            tx_out <= 1'b1;
            tx_ready <= 1'b1;
        end else begin
            case (state)
                IDLE: begin
                    tx_out <= 1'b1;
                    tx_ready <= 1'b1;
                    if (tx_valid) begin
                        shift_reg <= tx_data;
                        tx_ready <= 1'b0;
                    end
                end
                
                START_BIT: begin
                    tx_out <= 1'b0;  // Start bit
                    bit_counter <= '0;
                end
                
                DATA_BITS: begin
                    if (baud_tick) begin
                        tx_out <= shift_reg[0];
                        shift_reg <= {1'b0, shift_reg[7:1]};
                        bit_counter <= bit_counter + 1;
                    end
                end
                
                STOP_BIT: begin
                    tx_out <= 1'b1;  // Stop bit
                end
                
                default: begin
                    tx_out <= 1'b1;
                    tx_ready <= 1'b1;
                end
            endcase
        end
    end
    
    // Assertions for verification
    `ifdef FORMAL
        // Check that tx_out is only 0 during start bit or data transmission
        assert property (@(posedge clk) disable iff (!rst_n)
            (state == IDLE || state == STOP_BIT) |-> tx_out == 1'b1
        );
        
        // Check that ready signal is low during transmission
        assert property (@(posedge clk) disable iff (!rst_n)
            (state != IDLE) |-> tx_ready == 1'b0
        );
    `endif

endmodule

// Simple testbench
module uart_tx_tb;
    logic clk;
    logic rst_n;
    logic [7:0] tx_data;
    logic tx_valid;
    logic tx_ready;
    logic tx_out;
    
    // Instantiate DUT
    uart_tx #(
        .CLK_FREQ(1_000_000),
        .BAUD_RATE(9600)
    ) dut (.*);
    
    // Clock generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end
    
    // Test sequence
    initial begin
        rst_n = 0;
        tx_valid = 0;
        tx_data = 8'h00;
        
        #20 rst_n = 1;
        #50;
        
        // Send byte 0x55
        @(posedge clk);
        tx_data = 8'h55;
        tx_valid = 1;
        @(posedge clk);
        tx_valid = 0;
        
        wait(tx_ready);
        #1000;
        
        // Send byte 0xAA
        @(posedge clk);
        tx_data = 8'hAA;
        tx_valid = 1;
        @(posedge clk);
        tx_valid = 0;
        
        wait(tx_ready);
        #1000;
        
        $finish;
    end
    
    // Monitor
    initial begin
        $monitor("Time=%0t rst_n=%b tx_data=%h tx_valid=%b tx_ready=%b tx_out=%b", 
                 $time, rst_n, tx_data, tx_valid, tx_ready, tx_out);
    end

endmodule