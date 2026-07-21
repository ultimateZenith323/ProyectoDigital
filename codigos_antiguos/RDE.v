module RDE (
    input [7:0] data,
    input enable,
    input CLK,
    input start,
    input reset,
    output MOSI
);

    reg [7:0] RD;

    assign MOSI = RD[7];

    always @(posedge CLK, posedge start) begin
        if (start) begin
            RD <= 8'b0;
        end else begin
            if (reset) RD <= 8'b0;
            else if (enable) RD <= {RD[6:0], RD[7]};
            else RD <= data;
        end
    end

endmodule
