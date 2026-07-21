module RDS (
    input MISO,
    input CLK,
    input start,
    input reset,
    output [7:0] info
);

    reg [7:0] RD;
    assign info = RD;

    always @(negedge CLK, posedge start) begin
        if (start) begin
            RD <= 8'b00000000;
        end else begin
            if (reset) RD <= 8'b0;
            else RD <= {RD[6:0], MISO};
        end
    end
endmodule
